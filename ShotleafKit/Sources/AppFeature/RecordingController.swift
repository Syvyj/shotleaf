import AppKit
import CaptureKit
import Core
import Observation

/// Screen recording: pick an area; Shotleaf's frame around it and a capsule with the
/// time, Pause/Resume, Stop and Cancel next to it (both left out of the video); a red
/// Stop with the time in the menu bar. The same hotkey, the Stop item or the menu stops it.
@MainActor
@Observable
final class RecordingController: NSObject {
    enum Phase { case idle, busy, recording, paused }

    /// `busy`: picking the area, starting, pausing, resuming or finishing.
    private(set) var phase = Phase.idle

    @ObservationIgnored var finished: (URL) -> Void = { _ in }
    @ObservationIgnored var failed: (Error) -> Void = { _ in }

    @ObservationIgnored private let capture: ScreenCaptureService
    @ObservationIgnored private let recorder = ScreenRecorder()
    @ObservationIgnored private var frame: NSPanel?
    @ObservationIgnored private var controls: RecordingControls?
    @ObservationIgnored private var stopItem: NSStatusItem?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var clock = RecordedTime()
    /// macOS ended the stream while we were busy: stop once that's done.
    @ObservationIgnored private var endedBySystem = false

    init(capture: ScreenCaptureService) {
        self.capture = capture
    }

    /// Hotkey / menu: start when idle, stop while recording or paused.
    func toggle() {
        switch phase {
        case .idle: start()
        case .recording, .paused: stop()
        case .busy: break // a press while picking or starting/finishing
        }
    }

    private func start() {
        phase = .busy
        endedBySystem = false
        Task { [self] in
            do {
                let area = try await capture.pickRecordingArea()
                let (rect, visible) = Self.screenRect(of: area)
                let frame = RecordingChrome.frame(around: rect)
                let controls = RecordingControls()
                controls.place(around: rect, in: visible)
                controls.onPauseResume = { [weak self] in self?.pauseResume() }
                controls.onStop = { [weak self] in self?.stop() }
                controls.onCancel = { [weak self] in self?.cancel() }
                // On screen before the recorder looks up the windows to leave out.
                frame.orderFrontRegardless()
                controls.panel.orderFrontRegardless()
                (self.frame, self.controls) = (frame, controls)
                let url = TempFolder.recordings.new().appendingPathComponent("Recording.mp4")
                // Ended by the system (display gone, "Stop sharing"): finish as Stop does.
                try await recorder.start(area, to: url, excluding: [frame, controls.panel].map { CGWindowID($0.windowNumber) }) { [weak self] in
                    Task { @MainActor in self?.systemEnded() }
                }
                clock = RecordedTime()
                clock.run(at: .now)
                showStopItem()
                settle(.recording)
            } catch {
                hideChrome()
                phase = .idle
                if case AppError.cancelled = error { return }
                failed(error)
            }
        }
    }

    func pauseResume() {
        let pausing: Bool
        switch phase {
        case .recording: pausing = true; clock.pause(at: .now)
        case .paused: pausing = false
        default: return
        }
        phase = .busy
        refresh()
        Task { [self] in
            do {
                if pausing { try await recorder.pause() } else { try await recorder.resume(); clock.run(at: .now) }
                settle(pausing ? .paused : .recording)
            } catch {
                // Either way nothing is being written now: keep what was.
                clock.pause(at: .now)
                phase = .paused
                stop()
            }
        }
    }

    @objc func stop() {
        guard phase == .recording || phase == .paused else { return }
        phase = .busy
        hideChrome()
        Task { [self] in
            do { finished(try await recorder.stop()) } catch { failed(error) }
            phase = .idle
        }
    }

    /// Stop and throw the recording away: no window, no file.
    func cancel() {
        guard phase == .recording || phase == .paused else { return }
        phase = .busy
        hideChrome()
        Task { [self] in
            await recorder.cancel()
            phase = .idle
        }
    }

    private func systemEnded() {
        if phase == .busy { endedBySystem = true } else { stop() }
    }

    /// Out of `busy`; a stop the system asked for meanwhile happens now.
    private func settle(_ phase: Phase) {
        self.phase = phase
        refresh()
        if endedBySystem { stop() }
    }

    private func hideChrome() {
        frame?.orderOut(nil)
        frame = nil
        controls?.panel.orderOut(nil)
        controls = nil
        ticker?.cancel()
        ticker = nil
        if let stopItem { NSStatusBar.system.removeStatusItem(stopItem) }
        stopItem = nil
    }

    /// The recorded time on the capsule and in the menu bar.
    private func refresh() {
        let text = Self.elapsed(clock.elapsed(at: .now))
        let paused = phase != .recording
        controls?.show(time: text, paused: paused)
        stopItem?.button?.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: paused ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ])
    }

    // MARK: Menu bar

    private func showStopItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let title = String(localized: "Stop Recording")
        item.button?.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: title)?
            .withSymbolConfiguration(.init(paletteColors: [.systemRed]))
        item.button?.imagePosition = .imageLeading
        item.button?.toolTip = title
        item.button?.target = self
        item.button?.action = #selector(stop)
        stopItem = item
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(0.5))
            }
        }
    }

    /// "mm:ss".
    static func elapsed(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: Frame

    /// The area in Cocoa's global points, and its screen's visible frame.
    private static func screenRect(of area: RecordingArea) -> (CGRect, CGRect) {
        let screen = NSScreen.screens.first {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == area.displayID
        } ?? NSScreen.screens[0]
        // Top-left points of that screen → Cocoa's bottom-left global ones.
        let rect = CGRect(x: screen.frame.minX + area.rect.minX, y: screen.frame.maxY - area.rect.maxY,
                          width: area.rect.width, height: area.rect.height)
        return (rect, screen.visibleFrame)
    }
}

/// Recorded time: the running stretches only, pauses left out.
struct RecordedTime {
    private var banked: TimeInterval = 0
    private var since: Date?

    mutating func run(at now: Date) {
        if since == nil { since = now }
    }

    mutating func pause(at now: Date) {
        if let since { banked += now.timeIntervalSince(since) }
        since = nil
    }

    func elapsed(at now: Date) -> TimeInterval {
        banked + (since.map { now.timeIntervalSince($0) } ?? 0)
    }
}
