import AppKit
import Core
import SwiftUI

/// Opens screenshot preview windows and pinned screenshots. Each capture gets
/// its own window, so several can be open (and pinned) at once.
@MainActor
final class ScreenshotWindows {
    /// OCR / ask-AI hand-off to the panel.
    var onText: (ImagePayload) -> Void = { _ in }
    var onAsk: (ImagePayload) -> Void = { _ in }

    private var open: [ObjectIdentifier: NSPanel] = [:]

    func show(_ payload: ImagePayload) {
        guard let image = NSImage(data: payload.data) else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let scale = screen?.backingScaleFactor ?? 2
        let pixels = CGSize(width: payload.width, height: payload.height)
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        // Leave room for the header, toolbar and hints around the image.
        let room = CGSize(width: visible.width - 80, height: visible.height - Self.chromeHeight)
        let display = Self.fit(points: CGSize(width: pixels.width / scale, height: pixels.height / scale), in: room)
        let fileURL = Self.writeTempPNG(payload.data)

        var panel: NSPanel!
        let close: () -> Void = { [weak self] in self?.close(panel) }
        let actions = ScreenshotActions(
            copy: { Self.copy(payload.data) },
            save: { Self.save(payload.data) },
            pin: { [weak self] in
                close()
                self?.pin(image, size: CGSize(width: pixels.width / scale, height: pixels.height / scale), data: payload.data)
            },
            text: { [weak self] in close(); self?.onText(payload) },
            ask: { [weak self] in close(); self?.onAsk(payload) },
            close: close
        )
        panel = makePanel(ScreenshotView(image: image, pixelSize: pixels, fileURL: fileURL, displaySize: display, actions: actions))
        panel.setFrameOrigin(Self.placed(panel.frame.size, centeredIn: visible))
        present(panel)
    }

    private func pin(_ image: NSImage, size: CGSize, data: Data) {
        // Pinned copies start at their real size, capped so they don't cover the screen.
        let size = Self.fit(points: size, in: CGSize(width: 900, height: 700))
        var panel: NSPanel!
        panel = makePanel(PinnedScreenshotView(
            image: image, size: size,
            copy: { Self.copy(data) },
            close: { [weak self] in self?.close(panel) }
        ))
        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2))
        present(panel)
    }

    // MARK: Windows

    private func makePanel<V: View>(_ view: V) -> NSPanel {
        let panel = FloatingPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentView = hosting
        // Size from the fully laid-out SwiftUI view, *then* the caller places it.
        hosting.layoutSubtreeIfNeeded()
        panel.setContentSize(hosting.fittingSize)
        return panel
    }

    private func present(_ panel: NSPanel) {
        open[ObjectIdentifier(panel)] = panel
        panel.makeKeyAndOrderFront(nil)
    }

    private func close(_ panel: NSPanel?) {
        guard let panel else { return }
        panel.orderOut(nil)
        open[ObjectIdentifier(panel)] = nil
    }

    // MARK: Files & clipboard

    static func copy(_ png: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
    }

    /// Saves to the Desktop as "APILA 2026-10-08 at 16.50.12.png".
    static func save(_ png: Data, to folder: URL? = nil, now: Date = Date()) -> URL? {
        let folder = folder ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let url = folder.appendingPathComponent(fileName(now))
        return (try? png.write(to: url)) != nil ? url : nil
    }

    static func fileName(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "APILA \(f.string(from: date)).png"
    }

    /// ponytail: temp files stay until macOS cleans the temp dir — a drop target
    /// may read the file lazily, so deleting on close could break the drop.
    private static func writeTempPNG(_ png: Data) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName(Date()))
        try? png.write(to: url)
        return url
    }

    // MARK: Geometry

    /// Header + toolbar + hint line + padding around the image, in points.
    static let chromeHeight: CGFloat = 170

    /// Scales `points` down (never up) to fit `available` (tall captures shrink
    /// to the screen height, wide ones to its width).
    static func fit(points: CGSize, in available: CGSize) -> CGSize {
        let k = min(1, available.width / max(points.width, 1), available.height / max(points.height, 1))
        return CGSize(width: (points.width * k).rounded(), height: (points.height * k).rounded())
    }

    /// Centered in `frame`, but never sticking out of it.
    static func placed(_ size: CGSize, centeredIn frame: CGRect) -> NSPoint {
        let x = min(max(frame.midX - size.width / 2, frame.minX + 8), frame.maxX - size.width - 8)
        let y = min(max(frame.midY - size.height / 2, frame.minY + 8), frame.maxY - size.height - 8)
        return NSPoint(x: max(x, frame.minX), y: max(y, frame.minY))
    }
}
