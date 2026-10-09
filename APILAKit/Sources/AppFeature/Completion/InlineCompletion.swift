import AppKit
import ApplicationServices
import SwiftUI
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
/// Besides continuations: `:` or `;` opens an emoji picker (1–9 or a click
/// picks, letters filter), and a just-typed misspelled word gets a fix; mid-line, offers show as a badge under the
/// cursor instead of grey text (which would cover the words after it).
/// ponytail: no app-specific fixes yet.
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
    /// What's offered now: a continuation, or a quick fix (emoji, typo).
    enum Offer: Equatable {
        case completion(String)
        case fix(QuickFix)
    }
    private var offer: Offer? { didSet { tapState.hasSuggestion = offer != nil } }
    /// The text Tab would type (the live test reads it).
    var suggestion: String? {
        switch offer {
        case .completion(let text): text
        case .fix(let fix): fix.insert
        case nil: nil
        }
    }
    private var field: FocusedField?
    /// The open emoji picker: what was typed after `:` and what it offers.
    private var picker: (query: String, candidates: [EmojiShortcodes.Candidate])?
    /// The picker's emoji (the live test reads it).
    var pickerEmoji: [String]? { picker?.candidates.map(\.emoji) }
    private lazy var pickerPanel = EmojiPickerPanel { [weak self] index in self?.pickEmoji(index) }

    /// Settings: how bold suggestions are, quick fixes on/off, the user's style.
    var boldness = CompletionText.Boldness(0.5)
    var quickFixes = true
    let history = WritingHistory()
    /// The field last read, to remember its text when the user moves on.
    private var lastSeen: (key: String, app: String, text: String)?
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
        switch offer {
        case .completion(let text): accept(all ? text : CompletionText.nextWord(of: text).word)
        case .fix(let fix):
            Self.deleteBackward(fix.replacing)
            Self.type(fix.insert)
            hide()
            schedule() // then a continuation after the fixed word
        case nil: Self.postTab() // it was taken a moment ago: give Tab back
        }
    }

    /// Esc was swallowed.
    fileprivate func escape() { dismiss() }

    /// 1–9 (or Tab → 0, or a click) in the emoji picker.
    fileprivate func pickEmoji(_ index: Int) {
        guard let picker, picker.candidates.indices.contains(index) else { return }
        let emoji = picker.candidates[index].emoji
        Self.deleteBackward(picker.query.count + 1) // ":" + the letters
        Self.type(emoji)
        EmojiRecents.used(emoji)
        dismiss()
    }

    private func showPicker(query: String, in field: FocusedField) {
        let candidates = EmojiShortcodes.candidates(query, recents: EmojiRecents.list)
        guard !candidates.isEmpty else { closePicker(); return }
        picker = (query, candidates)
        hide()
        let frame = pickerPanel.show(candidates, under: field.caret)
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        tapState.picker = CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height) // tap's top-left space
    }

    private func closePicker() {
        picker = nil
        tapState.picker = nil
        pickerPanel.orderOut(nil)
    }

    fileprivate func clicked() { dismiss() } // a click moves the caret

    /// Any other key went through to the app.
    fileprivate func typed(_ typed: String, shortcut: Bool) {
        if shortcut { dismiss(); return }
        // Typing the suggested letters keeps the rest of the suggestion.
        if case .completion(let text) = offer, field?.afterCursor.isEmpty == true,
           let rest = CompletionText.advance(text, typed: typed) {
            offer = .completion(rest)
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
        rememberIfLeft(field)
        if quickFixes, let query = EmojiShortcodes.query(beforeCursor: field.beforeCursor) {
            showPicker(query: query, in: field)
            return
        }
        closePicker()
        if quickFixes, let fix = TypoFixer.fix(beforeCursor: field.beforeCursor) {
            show(.fix(fix), in: field)
            return
        }
        guard EmbeddedModel.completion.isDownloaded, CompletionText.shouldComplete(beforeCursor: field.beforeCursor),
              field.afterCursor.first?.isLetter != true // not in the middle of a word
        else { return }
        generation?.cancel()
        var promptContext = context.current(for: field)
        promptContext.afterCursor = field.afterCursor
        promptContext.examples = history.examples(for: field.bundleID, current: field.beforeCursor)
        let prompt = CompletionText.prompt(beforeCursor: field.beforeCursor, context: promptContext)
        let minProbability = boldness.minTokenProbability
        let id = generationID
        let started = ContinuousClock.now
        generation = Task { // the controller lives as long as the app
            do {
                // Shown word by word as the model writes; any key press bumps
                // `generationID` and the rest of this answer is ignored.
                let result = try await EmbeddedModel.completion.complete(prompt, minProbability: minProbability, onPartial: { partial in
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
              let text = CompletionText.suggestion(fromContinuation: raw, finished: finished, beforeCursor: field.beforeCursor,
                                                   afterCursor: field.afterCursor, maxWords: boldness.maxWords)
        else { return }
        // At the end of a line: what fits before the field's edge. Mid-line it's a badge.
        let visible = field.afterCursor.isEmpty ? GhostPanel.fitting(text, caret: field.caret, rightEdge: field.rightEdge) : text
        guard let visible else { return }
        if offer == nil { log.notice("first words in \(ContinuousClock.now - started, privacy: .public)") }
        show(.completion(visible), in: field)
    }

    private func show(_ offer: Offer, in field: FocusedField) {
        self.offer = offer
        self.field = field
        switch offer {
        case .completion(let text) where field.afterCursor.isEmpty: ghost.show(text: text, caret: field.caret)
        case .completion(let text): ghost.showBadge(text.trimmingCharacters(in: .whitespaces), caret: field.caret)
        case .fix(let fix): ghost.showBadge(fix.label, caret: field.caret)
        }
    }

    /// The user moved to another field: what they wrote there joins their style.
    private func rememberIfLeft(_ field: FocusedField) {
        let key = "\(field.pid)|\(CFHash(field.element))"
        if let lastSeen, lastSeen.key != key { history.remember(lastSeen.text, app: lastSeen.app) }
        lastSeen = (key, field.bundleID, field.beforeCursor + field.afterCursor)
    }

    private func reposition(after delay: Duration) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.offer != nil, let field = await Self.readField(), self.offer != nil else { return }
            self.field = field
            self.ghost.move(caret: field.caret)
        }
    }

    // MARK: Accept / dismiss

    private func accept(_ text: String) {
        // Mid-line the badge's text goes in after a space if the model meant one.
        Self.type(text)
        let rest = suggestion.map { String($0.dropFirst(text.count)) } ?? ""
        if rest.trimmingCharacters(in: .whitespaces).isEmpty {
            hide()
        } else {
            offer = .completion(rest)
            if field?.afterCursor.isEmpty == false {
                ghost.showBadge(rest.trimmingCharacters(in: .whitespaces), caret: field?.caret ?? .zero)
            } else {
                ghost.update(text: rest)
            }
            reposition(after: .milliseconds(60))
        }
    }

    /// Hides the suggestion (and picker) and forgets pending work.
    private func dismiss() {
        generationID += 1
        debounceTask?.cancel()
        generation?.cancel()
        hide()
        closePicker()
    }

    private func hide() {
        offer = nil
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

    /// Deletes `count` characters before the cursor (Backspace × count).
    private static func deleteBackward(_ count: Int) {
        for _ in 0..<count {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 51, keyDown: down) else { continue }
                event.setIntegerValueField(.eventSourceUserData, value: marker)
                event.post(tap: .cgSessionEventTap)
            }
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
    private var _picker: CGRect?
    /// The emoji picker's frame (global, top-left origin) while it's open.
    var picker: CGRect? {
        get { lock.withLock { _picker } }
        set { lock.withLock { _picker = newValue } }
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
    let bundleID: String
    let appName: String?
    let windowTitle: String
    /// The rest of the line after the cursor ("" at the end of a line).
    let afterCursor: String

    /// nil when there's no editable, non-secure field with an empty selection
    /// (or the app is excluded / APILA itself).
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
        // Plain fields (Cocoa, Qt…) expose their text as a value; web editors
        // (Chromium, Electron — Claude, Slack, Notion) only through text markers.
        guard let read = viaValue(element) ?? viaTextMarkers(element) else { return nil }
        let bounds = read.caret
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
        return FocusedField(element: element, beforeCursor: read.before, caret: caret, rightEdge: rightEdge,
                            pid: pid, bundleID: app.bundleIdentifier ?? "", appName: app.localizedName, windowTitle: title,
                            afterCursor: read.after)
    }

    /// Text before / after the cursor (rest of the line) and the box of the
    /// character before it (AX coordinates).
    private typealias Read = (before: String, after: String, caret: CGRect)

    /// The field's value and selected range, and the bounds of a character range.
    private static func viaValue(_ element: AXUIElement) -> Read? {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue,
              let value: String = attribute(element, kAXValueAttribute),
              let rangeValue: AXValue = attribute(element, kAXSelectedTextRangeAttribute)
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range), range.length == 0, range.location > 0 else { return nil }
        let text = value as NSString
        guard range.location <= text.length else { return nil }
        var charRange = CFRange(location: range.location - 1, length: 1)
        guard let query = AXValueCreate(.cfRange, &charRange),
              let bounds = rect(parameterized(element, kAXBoundsForRangeParameterizedAttribute, query)), bounds.height > 2
        else { return nil }
        let rest = text.substring(from: range.location)
        return (text.substring(to: range.location), String(rest.prefix { $0 != "\n" && $0 != "\r" }.prefix(200)), bounds)
    }

    /// Web editors: the selection as a text-marker range, the text from the
    /// start to it, and the bounds of the character just before it.
    private static func viaTextMarkers(_ element: AXUIElement) -> Read? {
        guard let selection = marker(element, "AXSelectedTextMarkerRange", AXTextMarkerRangeGetTypeID()).map({ $0 as! AXTextMarkerRange }),
              let start = marker(element, "AXStartTextMarker", AXTextMarkerGetTypeID()).map({ $0 as! AXTextMarker }),
              let end = marker(element, "AXEndTextMarker", AXTextMarkerGetTypeID()).map({ $0 as! AXTextMarker })
        else { return nil }
        let caretStart = AXTextMarkerRangeCopyStartMarker(selection)
        let caretEnd = AXTextMarkerRangeCopyEndMarker(selection)
        func string(_ from: AXTextMarker, _ to: AXTextMarker) -> String? {
            parameterized(element, "AXStringForTextMarkerRange", AXTextMarkerRangeCreate(nil, from, to)) as? String
        }
        guard string(caretStart, caretEnd)?.isEmpty != false, // no selection, just a cursor
              let before = string(start, caretStart), !before.isEmpty,
              let previousRef = parameterized(element, "AXPreviousTextMarkerForTextMarker", caretStart),
              CFGetTypeID(previousRef) == AXTextMarkerGetTypeID()
        else { return nil }
        let previous = previousRef as! AXTextMarker
        guard let bounds = rect(parameterized(element, "AXBoundsForTextMarkerRange", AXTextMarkerRangeCreate(nil, previous, caretStart))),
              bounds.height > 2
        else { return nil }
        let after = string(caretEnd, end) ?? ""
        return (before, String(after.prefix { $0 != "\n" && $0 != "\r" }.prefix(200)), bounds)
    }

    private static func marker(_ element: AXUIElement, _ name: String, _ type: CFTypeID) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value, CFGetTypeID(value) == type
        else { return nil }
        return value
    }

    private static func parameterized(_ element: AXUIElement, _ name: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &value) == .success else { return nil }
        return value
    }

    private static func rect(_ value: CFTypeRef?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
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
        label.wantsLayer = true
        label.layer?.cornerRadius = 5
        label.layer?.masksToBounds = true
        contentView = label
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private var caret = CGRect.zero

    func show(text: String, caret: CGRect) {
        self.caret = caret
        label.textColor = NSColor.tertiaryLabelColor
        label.drawsBackground = false
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
        badge = false
        label.stringValue = text
        layoutAtCaret()
    }

    /// Mid-line or a quick fix: a small "⇥ text" badge just under the caret.
    func showBadge(_ text: String, caret: CGRect) {
        self.caret = caret
        badge = true
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.stringValue = "⇥  " + text
        label.textColor = .labelColor
        label.drawsBackground = true
        label.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
        layoutAtCaret()
        orderFrontRegardless()
    }

    private var badge = false

    func move(caret: CGRect) {
        self.caret = caret
        layoutAtCaret()
    }

    private func layoutAtCaret() {
        let size = label.intrinsicContentSize
        if badge { // under the caret, slightly left so the ⇥ sits below it
            setFrame(CGRect(x: caret.maxX - 6, y: caret.minY - size.height - 4, width: size.width + 8, height: size.height + 2), display: true)
            return
        }
        let y = caret.minY + (caret.height - size.height) / 2
        setFrame(CGRect(x: caret.maxX, y: y, width: size.width + 4, height: size.height), display: true)
    }
}

/// The emoji picker under the cursor, in the Leaves style: "1 👍  2 😂 …";
/// the first one (what Tab takes) is highlighted, a click picks too. Never
/// takes the keyboard — the user keeps typing in their app.
@MainActor
final class EmojiPickerPanel: NSPanel {
    private let onPick: (Int) -> Void

    init(onPick: @escaping (Int) -> Void) {
        self.onPick = onPick
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows the candidates under `caret` (AppKit screen coordinates) and
    /// returns the panel's frame.
    func show(_ candidates: [EmojiShortcodes.Candidate], under caret: CGRect) -> CGRect {
        let host = FirstClickHostingView(rootView: EmojiPickerRow(candidates: candidates, onPick: onPick))
        contentView = host
        let size = host.fittingSize
        let frame = CGRect(x: caret.minX - 8, y: caret.minY - size.height - 6, width: size.width, height: size.height)
        setFrame(frame, display: true)
        orderFrontRegardless()
        return frame
    }
}

/// A click on the picker counts even though its window never becomes key.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct EmojiPickerRow: View {
    let candidates: [EmojiShortcodes.Candidate]
    let onPick: (Int) -> Void
    @State private var hovered: Int?
    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(candidates.enumerated()), id: \.offset) { i, candidate in
                Button { onPick(i) } label: {
                    HStack(spacing: 3) {
                        Text(verbatim: "\(i + 1)")
                            .font(Leaf.font(10, .bold))
                            .foregroundStyle(Leaf.ink)
                        Text(verbatim: candidate.emoji).font(.system(size: 19))
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background {
                        let on = hovered.map { $0 == i } ?? (i == 0) // Tab takes the first
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(on ? AnyShapeStyle(Leaf.selection) : AnyShapeStyle(.clear))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? i : (hovered == i ? nil : hovered) }
                .help(candidate.name.replacingOccurrences(of: "_", with: " "))
            }
        }
        .padding(5)
        .background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Leaf.surface)
                shape.fill(LinearGradient(colors: [Leaf.fresh.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom))
            }
        }
        .overlay(shape.strokeBorder(Leaf.markGradient, lineWidth: 1).opacity(0.55))
        .clipShape(shape)
        .fixedSize()
    }
}
