import AppKit
import ApplicationServices
import EmbeddedKit
import OSLog

/// System-wide inline completion (Cotypist-style): while you type in any app,
/// the built-in model suggests how the line goes on, shown as grey "ghost"
/// text right after the cursor. Tab accepts the next word (⌥Tab — all of it),
/// typing the same letters keeps it, anything else or Esc drops it.
///
/// How: a keyboard event tap (needs Accessibility) on its own thread watches
/// keys and catches Tab while a suggestion is up — it never waits for anything,
/// so typing can't lag. The focused field's text and caret are read through
/// the Accessibility API off the main thread (slow apps answer slowly);
/// accepted text is typed as synthetic key events.
/// Runs only on the built-in model — your text never leaves the Mac.
/// ponytail: suggests only at the end of a line, no app-specific fixes yet.
@MainActor
final class InlineCompletion {
    private let log = Logger(subsystem: "app.apila.APILA", category: "completion")
    /// Marks APILA's own synthetic key events so the tap lets them through.
    nonisolated fileprivate static let marker: Int64 = 0x4150_494C // "APIL"
    /// The model answers in ~50 ms now; waiting longer only feels slow.
    private static let debounce: Duration = .milliseconds(60)

    /// Apps where completion only gets in the way.
    nonisolated private static let excluded: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty",
        "com.mitchellh.ghostty", "io.alacritty", "com.apple.keychainaccess", "com.1password.1password",
    ]
    /// Chromium browsers expose their text to Accessibility only on request.
    private static let chromium: Set<String> = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    private var tapThread: EventTapThread?
    /// Shared with the tap thread: is a suggestion up (so Tab is ours)?
    fileprivate let tapState = TapState()
    private var debounceTask: Task<Void, Never>?
    private var generation: Task<Void, Never>?
    /// Bumped by every key press: partial results of an older request are dropped.
    private var generationID = 0
    private let ghost = GhostPanel()
    /// Screen text, clipboard, app — what the model knows besides the field.
    let context = CompletionContext()
    /// What's on screen now, and where it belongs.
    private var suggestion: String? { didSet { tapState.hasSuggestion = suggestion != nil } }
    private var field: FocusedField?
    private var activationObserver: NSObjectProtocol?

    var isRunning: Bool { tapThread != nil }

    /// Starts watching. False when macOS refuses the event tap (no Accessibility).
    @discardableResult
    func start() -> Bool {
        guard tapThread == nil else { return true }
        tapState.controller = self
        let thread = EventTapThread(state: tapState)
        guard thread.startAndWait() else {
            log.error("event tap refused — Accessibility off?")
            return false
        }
        tapThread = thread
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.dismiss()
                if let app { Self.exposeAccessibility(of: app) }
            }
        }
        if let front = NSWorkspace.shared.frontmostApplication { Self.exposeAccessibility(of: front) }
        log.info("inline completion on")
        return true
    }

    func stop() {
        dismiss()
        tapThread?.stop()
        tapThread = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
    }

    // MARK: Keys (from the tap thread, in order, on main)

    /// Tab was swallowed because a suggestion was up.
    fileprivate func tab(all: Bool) {
        guard let suggestion else { Self.postTab(); return } // it was taken a moment ago: give Tab back
        accept(all ? suggestion : CompletionText.nextWord(of: suggestion).word)
    }

    /// Esc was swallowed.
    fileprivate func escape() { dismiss() }

    fileprivate func clicked() { dismiss() } // a click moves the caret

    /// Any other key went through to the app.
    fileprivate func typed(_ typed: String, shortcut: Bool) {
        if shortcut { dismiss(); return }
        // Typing the suggested letters keeps the rest of the suggestion.
        if let suggestion, let rest = CompletionText.advance(suggestion, typed: typed) {
            self.suggestion = rest
            ghost.update(text: rest)
            reposition(after: .milliseconds(30))
        } else {
            hide()
        }
        schedule()
    }

    nonisolated fileprivate static func characters(of event: CGEvent) -> String {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &chars)
        return String(utf16CodeUnits: chars, count: length)
    }

    // MARK: Suggest

    private func schedule() {
        generationID += 1
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let field = await Self.readField() else { return }
            guard !Task.isCancelled else { return }
            self?.suggest(in: field)
        }
    }

    /// The focused field, read off the main thread: some apps take a while
    /// to answer Accessibility queries.
    private static func readField() async -> FocusedField? {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return await Task.detached { FocusedField.current(excluding: excluded, screenTop: top) }.value
    }

    private func suggest(in field: FocusedField) {
        guard EmbeddedModel.completion.isDownloaded, CompletionText.shouldComplete(beforeCursor: field.beforeCursor) else { return }
        generation?.cancel()
        let prompt = CompletionText.prompt(beforeCursor: field.beforeCursor, context: context.current(for: field))
        let id = generationID
        let started = ContinuousClock.now
        generation = Task { // the controller lives as long as the app
            do {
                // Shown word by word as the model writes; any key press bumps
                // `generationID` and the rest of this answer is ignored.
                let result = try await EmbeddedModel.completion.complete(prompt, onPartial: { partial in
                    Task { @MainActor in self.update(partial, finished: false, id: id, in: field, started: started) }
                })
                guard !Task.isCancelled else { return }
                update(result.text, finished: result.finished, id: id, in: field, started: started)
                log.notice("suggestion done in \(ContinuousClock.now - started, privacy: .public)")
            } catch {
                log.error("completion failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func update(_ raw: String, finished: Bool, id: Int, in field: FocusedField, started: ContinuousClock.Instant) {
        guard id == generationID,
              let text = CompletionText.suggestion(fromContinuation: raw, finished: finished, beforeCursor: field.beforeCursor),
              let visible = GhostPanel.fitting(text, caret: field.caret, rightEdge: field.rightEdge) // stop at the field's edge
        else { return }
        if suggestion == nil { log.notice("first words in \(ContinuousClock.now - started, privacy: .public)") }
        show(visible, in: field)
    }

    private func show(_ text: String, in field: FocusedField) {
        suggestion = text
        self.field = field
        ghost.show(text: text, caret: field.caret)
    }

    private func reposition(after delay: Duration) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.suggestion != nil, let field = await Self.readField(), self.suggestion != nil else { return }
            self.field = field
            self.ghost.move(caret: field.caret)
        }
    }

    // MARK: Accept / dismiss

    private func accept(_ text: String) {
        Self.type(text)
        let rest = suggestion.map { String($0.dropFirst(text.count)) } ?? ""
        if rest.trimmingCharacters(in: .whitespaces).isEmpty {
            hide()
        } else {
            suggestion = rest
            ghost.update(text: rest)
            reposition(after: .milliseconds(60))
        }
    }

    /// Hides the suggestion and forgets pending work.
    private func dismiss() {
        generationID += 1
        debounceTask?.cancel()
        generation?.cancel()
        hide()
    }

    private func hide() {
        suggestion = nil
        field = nil
        ghost.orderOut(nil)
    }

    /// Types `text` into the focused app as key events (works where pasting
    /// or Accessibility writes don't, and keeps the app's own undo).
    private static func type(_ text: String) {
        let units = Array(text.utf16)
        var start = 0
        while start < units.count {
            let chunk = Array(units[start ..< min(start + 16, units.count)])
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { continue }
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event.setIntegerValueField(.eventSourceUserData, value: marker)
                event.post(tap: .cgSessionEventTap)
            }
            start += 16
        }
    }

    /// Gives a swallowed Tab back to the app.
    private static func postTab() {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: down) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cgSessionEventTap)
        }
    }

    /// Chromium and Electron apps build their accessibility tree only when
    /// asked; without it there's no text or caret to read.
    private static func exposeAccessibility(of app: NSRunningApplication) {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if let id = app.bundleIdentifier, chromium.contains(id) {
            AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }
}

/// What the tap thread needs to decide on its own, at once.
private final class TapState: @unchecked Sendable {
    private let lock = NSLock()
    private var _hasSuggestion = false
    var hasSuggestion: Bool {
        get { lock.withLock { _hasSuggestion } }
        set { lock.withLock { _hasSuggestion = newValue } }
    }
    weak var controller: InlineCompletion?
    var port: CFMachPort?

    /// On the tap thread: swallow? Everything else is handed to main.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        }
        let controller = self.controller
        guard type == .keyDown else {
            DispatchQueue.main.async { MainActor.assumeIsolated { controller?.clicked() } }
            return false
        }
        if event.getIntegerValueField(.eventSourceUserData) == InlineCompletion.marker { return false }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
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
private final class EventTapThread: Thread, @unchecked Sendable {
    private let state: TapState
    private let ready = DispatchSemaphore(value: 0)
    private var ok = false
    private var runLoop: CFRunLoop?

    init(state: TapState) {
        self.state = state
        super.init()
        name = "APILA completion keys"
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

/// The text field that has the keyboard, read through Accessibility.
/// Immutable; the AX element is a CF reference, safe to pass between threads.
struct FocusedField: @unchecked Sendable {
    let element: AXUIElement
    let beforeCursor: String
    /// The character before the caret, in AppKit screen coordinates.
    let caret: CGRect
    /// The field's right edge (screen x): suggestions stop there.
    let rightEdge: CGFloat
    let pid: pid_t
    let appName: String?
    let windowTitle: String

    /// nil when there's no editable, non-secure field with an empty selection
    /// at the end of a line (or the app is excluded / APILA itself).
    /// Safe off the main thread; `screenTop` is the main screen's top (AppKit).
    static func current(excluding excluded: Set<String>, screenTop top: CGFloat) -> FocusedField? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2) // a hung app must not freeze typing
        guard let element: AXUIElement = attribute(system, kAXFocusedUIElementAttribute) else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != getpid(), let app = NSRunningApplication(processIdentifier: pid),
              !excluded.contains(app.bundleIdentifier ?? "")
        else { return nil }
        if let subrole: String = attribute(element, kAXSubroleAttribute), subrole == kAXSecureTextFieldSubrole { return nil }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue,
              let value: String = attribute(element, kAXValueAttribute),
              let rangeValue: AXValue = attribute(element, kAXSelectedTextRangeAttribute)
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range), range.length == 0, range.location > 0 else { return nil }
        let text = value as NSString
        guard range.location <= text.length else { return nil }
        // Only at the end of a line: mid-sentence suggestions would overlap the text after.
        if range.location < text.length {
            let next = text.character(at: range.location)
            guard next == 10 || next == 13 else { return nil }
        }
        var charRange = CFRange(location: range.location - 1, length: 1)
        guard let query = AXValueCreate(.cfRange, &charRange) else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, query, &boundsRef) == .success,
              let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID()
        else { return nil }
        var bounds = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &bounds), bounds.height > 2 else { return nil }
        // AX uses top-left global coordinates; AppKit — bottom-left of the main screen.
        let caret = CGRect(x: bounds.minX, y: top - bounds.maxY, width: bounds.width, height: bounds.height)
        var rightEdge = caret.maxX + 600
        if let position: AXValue = attribute(element, kAXPositionAttribute), let size: AXValue = attribute(element, kAXSizeAttribute) {
            var origin = CGPoint.zero, extent = CGSize.zero
            if AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &extent), extent.width > 0 {
                rightEdge = origin.x + extent.width
            }
        }
        var title = ""
        if let window: AXUIElement = attribute(element, kAXWindowAttribute), let t: String = attribute(window, kAXTitleAttribute) { title = t }
        return FocusedField(element: element, beforeCursor: text.substring(to: range.location), caret: caret, rightEdge: rightEdge,
                            pid: pid, appName: app.localizedName, windowTitle: title)
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}

/// The grey suggestion right after the caret: a click-through, never-key panel.
@MainActor
final class GhostPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        label.textColor = NSColor.tertiaryLabelColor
        label.lineBreakMode = .byClipping
        contentView = label
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private var caret = CGRect.zero

    func show(text: String, caret: CGRect) {
        self.caret = caret
        // Roughly the field's font: a line is ~1.2× the font size.
        label.font = Self.font(for: caret)
        update(text: text)
        orderFrontRegardless()
    }

    /// Roughly the field's font: a line is ~1.2× the font size.
    static func font(for caret: CGRect) -> NSFont { .systemFont(ofSize: min(max(caret.height / 1.22, 11), 30)) }

    /// The words of `text` that fit between the caret and `rightEdge`; nil if
    /// not even the first one does.
    static func fitting(_ text: String, caret: CGRect, rightEdge: CGFloat) -> String? {
        let room = rightEdge - caret.maxX - 8
        let attributes: [NSAttributedString.Key: Any] = [.font: font(for: caret)]
        var candidate = text
        while !candidate.trimmingCharacters(in: .whitespaces).isEmpty {
            if NSAttributedString(string: candidate, attributes: attributes).size().width <= room { return candidate }
            guard let cut = candidate.lastIndex(where: \.isWhitespace), cut > candidate.startIndex else { return nil }
            candidate = String(candidate[..<cut])
        }
        return nil
    }

    func update(text: String) {
        label.stringValue = text
        layoutAtCaret()
    }

    func move(caret: CGRect) {
        self.caret = caret
        layoutAtCaret()
    }

    private func layoutAtCaret() {
        let size = label.intrinsicContentSize
        let y = caret.minY + (caret.height - size.height) / 2
        setFrame(CGRect(x: caret.maxX, y: y, width: size.width + 4, height: size.height), display: true)
    }
}
