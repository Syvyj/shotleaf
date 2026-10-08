import AppKit
import Core
import ScreenCaptureKit

/// Shottr-style region picker: freezes every screen first (so menus and
/// tooltips stay put), then shows a full-screen overlay per display where the
/// user drags a region, clicks a window, takes the whole screen, or repeats the
/// last region.
@MainActor
final class RegionPicker {
    static let shared = RegionPicker()

    /// Last picked region (display + view rect) for "R — repeat".
    /// ponytail: in memory only; persist if users want it across launches.
    private var last: (displayID: CGDirectDisplayID, rect: CGRect)?

    private var windows: [NSPanel] = []
    private var continuation: CheckedContinuation<CGImage, Error>?

    func pick() async throws -> CGImage {
        guard continuation == nil else { throw AppError.cancelled } // already picking
        let frozen = try await freezeScreens()
        guard !frozen.isEmpty else { throw AppError.missingContext("No screen to capture") }
        let windowFrames = Self.onScreenWindowFrames()

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            show(frozen, windowFrames: windowFrames)
        }
    }

    // MARK: Freeze

    private struct Frozen {
        let screen: NSScreen
        let displayID: CGDirectDisplayID
        let image: CGImage
        /// The screen in CG-global coordinates (top-left origin of the primary display).
        let globalFrame: CGRect
    }

    private func freezeScreens() async throws -> [Frozen] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw AppError.permissionDenied("Screen Recording")
        }
        // Never capture APILA's own panel, even if it hasn't finished hiding.
        let ownApps = content.applications.filter { $0.processID == getpid() }

        var frozen: [Frozen] = []
        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let display = content.displays.first(where: { $0.displayID == displayID })
            else { continue }
            let scale = screen.backingScaleFactor
            let config = SCStreamConfiguration()
            config.width = Int(CGFloat(display.width) * scale)
            config.height = Int(CGFloat(display.height) * scale)
            config.showsCursor = false
            config.captureResolution = .best
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            frozen.append(Frozen(screen: screen, displayID: displayID, image: image, globalFrame: CGDisplayBounds(displayID)))
        }
        return frozen
    }

    /// Normal app windows, front to back, in CG-global coordinates.
    private static func onScreenWindowFrames() -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != getpid(),
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width >= 40, rect.height >= 40
            else { return nil }
            return rect
        }
    }

    // MARK: Overlay

    private func show(_ frozen: [Frozen], windowFrames: [CGRect]) {
        for item in frozen {
            let size = item.screen.frame.size
            let local = windowFrames
                .filter { $0.intersects(item.globalFrame) }
                .map { CaptureGeometry.viewRect(fromGlobal: $0, screen: item.globalFrame) }
            let view = SelectionView(
                frame: CGRect(origin: .zero, size: size),
                image: item.image,
                scale: item.screen.backingScaleFactor,
                windows: local,
                canRepeat: last != nil
            ) { [weak self] outcome in
                self?.complete(outcome, on: item, frozen: frozen)
            }
            let window = OverlayWindow(
                contentRect: item.screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
            )
            window.level = .screenSaver
            window.hidesOnDeactivate = false
            window.isFloatingPanel = true
            window.isOpaque = true
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.acceptsMouseMovedEvents = true
            window.contentView = view
            window.setFrame(item.screen.frame, display: false)
            window.orderFrontRegardless()
            windows.append(window)
        }
        // Non-activating panels take the keyboard without activating APILA —
        // macOS may refuse to activate us (cooperative activation), and then
        // Esc / Return would go to the app underneath.
        // Keyboard goes to the screen under the mouse.
        let mouse = NSEvent.mouseLocation
        let keyWindow = windows.first { $0.frame.contains(mouse) } ?? windows.first
        keyWindow?.makeKeyAndOrderFront(nil)
        keyWindow?.makeFirstResponder(keyWindow?.contentView)
        NSCursor.crosshair.set()
    }

    private func complete(_ outcome: SelectionView.Outcome, on item: Frozen, frozen: [Frozen]) {
        let result: Result<CGImage, Error>
        switch outcome {
        case .cancel:
            result = .failure(AppError.cancelled)
        case .region(let rect):
            last = (item.displayID, rect)
            result = Self.crop(item, rect)
        case .repeatLast:
            if let last, let target = frozen.first(where: { $0.displayID == last.displayID }) {
                result = Self.crop(target, last.rect)
            } else {
                result = .failure(AppError.cancelled)
            }
        }
        windows.forEach { $0.orderOut(nil) }
        windows = []
        NSCursor.arrow.set()
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }

    private static func crop(_ item: Frozen, _ rect: CGRect) -> Result<CGImage, Error> {
        let pixels = CaptureGeometry.pixelRect(
            fromView: rect,
            scale: item.screen.backingScaleFactor,
            imageSize: CGSize(width: item.image.width, height: item.image.height)
        )
        guard !pixels.isEmpty, let cropped = item.image.cropping(to: pixels) else {
            return .failure(AppError.cancelled)
        }
        return .success(cropped)
    }
}

/// Borderless panels can't become key by default — the picker needs keys.
private final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
