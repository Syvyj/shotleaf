import AppKit
import CaptureKit
import Core
import Observation

/// Screen recording: pick an area, a thin frame around it (left out of the
/// video), a red Stop with the time in the menu bar. The same hotkey, the Stop
/// item or the menu stops it.
@MainActor
@Observable
final class RecordingController: NSObject {
    enum Phase { case idle, busy, recording }

    /// `busy`: picking the area, starting or finishing.
    private(set) var phase = Phase.idle

    @ObservationIgnored var finished: (URL) -> Void = { _ in }
    @ObservationIgnored var failed: (Error) -> Void = { _ in }

    @ObservationIgnored private let capture: ScreenCaptureService
    @ObservationIgnored private let recorder = ScreenRecorder()
    @ObservationIgnored private var frame: NSPanel?
    @ObservationIgnored private var stopItem: NSStatusItem?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    init(capture: ScreenCaptureService) {
        self.capture = capture
    }

    /// Hotkey / menu: start when idle, stop while recording.
    func toggle() {
        switch phase {
        case .idle: start()
        case .recording: stop()
        case .busy: break // a press while picking or starting/finishing
        }
    }

    private func start() {
        phase = .busy
        Task {
            do {
                let area = try await capture.pickRecordingArea()
                let frame = Self.frame(around: area)
                self.frame = frame
                let url = TempFolder.recordings.new().appendingPathComponent("Recording.mp4")
                try await recorder.start(area, to: url, excluding: [CGWindowID(frame.windowNumber)])
                showStopItem()
                phase = .recording
            } catch {
                hideChrome()
                phase = .idle
                if case AppError.cancelled = error { return }
                failed(error)
            }
        }
    }

    @objc func stop() {
        guard phase == .recording else { return }
        phase = .busy
        hideChrome()
        Task {
            do { finished(try await recorder.stop()) } catch { failed(error) }
            phase = .idle
        }
    }

    private func hideChrome() {
        frame?.orderOut(nil)
        frame = nil
        ticker?.cancel()
        ticker = nil
        if let stopItem { NSStatusBar.system.removeStatusItem(stopItem) }
        stopItem = nil
    }

    // MARK: Menu bar

    private func showStopItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let title = String(localized: "Stop Recording")
        item.button?.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: title)?
            .withSymbolConfiguration(.init(paletteColors: [.systemRed]))
        item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        item.button?.toolTip = title
        item.button?.target = self
        item.button?.action = #selector(stop)
        stopItem = item
        let began = Date()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                stopItem?.button?.title = Self.elapsed(Date().timeIntervalSince(began))
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// "mm:ss".
    static func elapsed(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: Frame

    /// A thin line just outside the area; it ignores the mouse.
    private static func frame(around area: RecordingArea) -> NSPanel {
        let width: CGFloat = 2
        let screen = NSScreen.screens.first {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == area.displayID
        } ?? NSScreen.screens[0]
        // Top-left points of that screen → Cocoa's bottom-left global ones.
        let rect = CGRect(x: screen.frame.minX + area.rect.minX, y: screen.frame.maxY - area.rect.maxY,
                          width: area.rect.width, height: area.rect.height).insetBy(dx: -width, dy: -width)
        let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = NSView(frame: CGRect(origin: .zero, size: rect.size))
        view.wantsLayer = true
        view.layer?.borderColor = NSColor.systemRed.cgColor
        view.layer?.borderWidth = width
        panel.contentView = view
        panel.orderFrontRegardless()
        return panel
    }
}
