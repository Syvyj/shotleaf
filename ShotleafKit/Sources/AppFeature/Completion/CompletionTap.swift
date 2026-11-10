import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// What the tap thread needs to decide on its own, at once.
final class TapState: @unchecked Sendable {
    private let lock = NSLock()
    private var _hasSuggestion = false
    var hasSuggestion: Bool {
        get { lock.withLock { _hasSuggestion } }
        set { lock.withLock { _hasSuggestion = newValue } }
    }
    private var _picker: CGRect?
    /// The emoji picker's frame (global, top-left origin) while it's open.
    var picker: CGRect? {
        get { lock.withLock { _picker } }
        set { lock.withLock { _picker = newValue } }
    }
    private weak var _controller: InlineCompletion?
    /// Set on main, read on the tap thread: behind the lock like the rest.
    var controller: InlineCompletion? {
        get { lock.withLock { _controller } }
        set { lock.withLock { _controller = newValue } }
    }
    private var _port: CFMachPort?
    var port: CFMachPort? {
        get { lock.withLock { _port } }
        set { lock.withLock { _port = newValue } }
    }

    /// On the tap thread: swallow? Everything else is handed to main.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        }
        let controller = self.controller
        guard type == .keyDown else {
            if let picker, picker.contains(event.location) { return false } // a click on the picker picks
            DispatchQueue.main.async { MainActor.assumeIsolated { controller?.clicked() } }
            return false
        }
        if event.getIntegerValueField(.eventSourceUserData) == InlineCompletion.marker { return false }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        if picker != nil, flags.isDisjoint(with: [.maskCommand, .maskControl]) {
            let digit = Int(InlineCompletion.characters(of: event)).flatMap { (1...9).contains($0) ? $0 - 1 : nil }
            if let index = digit ?? (key == 48 ? 0 : nil) { // 1–9, or Tab for the first
                DispatchQueue.main.async { MainActor.assumeIsolated { controller?.pickEmoji(index) } }
                return true
            }
            if key == 53 { // Esc
                DispatchQueue.main.async { MainActor.assumeIsolated { controller?.escape() } }
                return true
            }
        }
        if hasSuggestion {
            if key == 48, flags.isDisjoint(with: [.maskCommand, .maskControl, .maskShift]) { // Tab
                let all = flags.contains(.maskAlternate)
                DispatchQueue.main.async { MainActor.assumeIsolated { controller?.tab(all: all) } }
                return true
            }
            if key == 53 { // Esc
                DispatchQueue.main.async { MainActor.assumeIsolated { controller?.escape() } }
                return true
            }
        }
        let typed = InlineCompletion.characters(of: event)
        let shortcut = !flags.isDisjoint(with: [.maskCommand, .maskControl])
        DispatchQueue.main.async { MainActor.assumeIsolated { controller?.typed(typed, shortcut: shortcut) } }
        return false
    }
}

/// Runs the keyboard event tap on its own run loop, so a busy main thread
/// never holds up the user's typing.
final class EventTapThread: Thread, @unchecked Sendable {
    private let state: TapState
    private let ready = DispatchSemaphore(value: 0)
    private var ok = false
    private var runLoop: CFRunLoop?

    init(state: TapState) {
        self.state = state
        super.init()
        name = "Shotleaf completion keys"
        qualityOfService = .userInteractive
    }

    /// Starts the thread; false when macOS refuses the tap.
    func startAndWait() -> Bool {
        start()
        ready.wait()
        return ok
    }

    override func main() {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask), callback: inlineCompletionTapCallback,
            userInfo: Unmanaged.passUnretained(state).toOpaque()
        ) else {
            ready.signal()
            return
        }
        state.port = port
        runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runLoop, CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        ok = true
        ready.signal()
        CFRunLoopRun()
    }

    func stop() {
        if let port = state.port { CGEvent.tapEnable(tap: port, enable: false) }
        state.port = nil
        if let runLoop { CFRunLoopStop(runLoop) }
    }
}

/// C callback → `TapState.handle`, on the tap thread.
private func inlineCompletionTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let state = Unmanaged<TapState>.fromOpaque(refcon).takeUnretainedValue()
    return state.handle(type, event) ? nil : Unmanaged.passUnretained(event)
}
