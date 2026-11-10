import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SwiftUI
import EmbeddedKit
import OSLog

/// System-wide inline completion: while you type in any app,
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
    private let log = Logger(subsystem: "dev.syvyj.shotleaf", category: "completion")
    /// Marks Shotleaf's own synthetic key events so the tap lets them through.
    nonisolated static let marker = Paster.marker
    /// The model answers in ~50 ms now; waiting longer only feels slow.
    private static let debounce: Duration = .milliseconds(60)

    /// Apps where completion only gets in the way (terminals), always; plus
    /// the user's "Never in these apps" list, shared with the clipboard history.
    nonisolated static let alwaysExcluded: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty",
        "com.mitchellh.ghostty", "io.alacritty",
    ]
    nonisolated static func excludedApps(_ defaults: UserDefaults = .standard) -> Set<String> {
        alwaysExcluded.union(ClipboardHistory.excludedApps(defaults))
    }
    /// Secure input is on (a password field, sudo in a terminal, a password
    /// manager): macOS hides the keys from the tap, and Shotleaf reads no field
    /// either, so nothing typed then can end up in a suggestion.
    nonisolated static var inputIsSecure: Bool { IsSecureEventInputEnabled() }
    /// Chromium browsers expose their text to Accessibility only on request.
    private static let chromium: Set<String> = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    private var tapThread: EventTapThread?
    /// Shared with the tap thread: is a suggestion up (so Tab is ours)?
    private let tapState = TapState()
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
    func tab(all: Bool) {
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
    func escape() { dismiss() }

    /// 1–9 (or Tab → 0, or a click) in the emoji picker.
    func pickEmoji(_ index: Int) {
        guard let picker, picker.candidates.indices.contains(index) else { return }
        let emoji = picker.candidates[index].emoji
        Self.deleteBackward(picker.query.count + 1) // ":" + the letters
        Self.type(emoji)
        EmojiRecents.used(emoji)
        dismiss()
    }

    private func showPicker(query: String, in field: FocusedField) {
        let wasOpen = picker?.query == query
        let candidates = EmojiShortcodes.candidates(query, recents: EmojiRecents.list)
        guard !candidates.isEmpty else { closePicker(); return }
        if !wasOpen { present(candidates, query: query, in: field) }
        // Just ":" — ask the model which emoji fit the text, and put those first.
        guard query.isEmpty, !wasOpen, EmbeddedModel.completion.isDownloaded else { return }
        let text = String(field.beforeCursor.dropLast()) // without the ":"
        guard text.trimmingCharacters(in: .whitespaces).count >= 3 else { return }
        let id = generationID
        Task {
            guard let answer = try? await EmbeddedModel.completion.complete(ContextEmoji.prompt(for: text), maxTokens: 14, minProbability: 0),
                  id == generationID, picker?.query == ""
            else { return }
            let emoji = ContextEmoji.merged(ContextEmoji.parse(answer.text), recents: EmojiRecents.list)
            let candidates = emoji.map { e in EmojiShortcodes.Candidate(emoji: e, name: EmojiShortcodes.all.first { $0.emoji == e }?.name ?? "") }
            present(candidates, query: "", in: field)
        }
    }

    private func present(_ candidates: [EmojiShortcodes.Candidate], query: String, in field: FocusedField) {
        picker = (query, candidates)
        hide()
        let frame = pickerPanel.show(candidates, under: field.caret)
        log.notice("emoji picker in \(field.bundleID, privacy: .public) via \(field.via, privacy: .public) at \("\(frame)", privacy: .public)")
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        tapState.picker = CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height) // tap's top-left space
    }

    private func closePicker() {
        picker = nil
        tapState.picker = nil
        pickerPanel.orderOut(nil)
    }

    func clicked() { dismiss() } // a click moves the caret

    /// Any other key went through to the app.
    func typed(_ typed: String, shortcut: Bool) {
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

    nonisolated static func characters(of event: CGEvent) -> String {
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
        guard !inputIsSecure else { return nil }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let excluded = excludedApps()
        return await Task.detached { FocusedField.current(excluding: excluded, screenTop: top) }.value
    }

    private func suggest(in field: FocusedField) {
        // Only with the model in place: without it nothing would use what's kept.
        if EmbeddedModel.completion.isDownloaded { rememberIfLeft(field) }
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
        if self.offer == nil {
            let screens = NSScreen.screens.map { "\($0.frame)" }.joined(separator: " ")
            log.notice("show in \(field.bundleID, privacy: .public) via \(field.via, privacy: .public): ax caret \("\(field.axCaret)", privacy: .public) → \("\(field.caret)", privacy: .public), after cursor \(field.afterCursor.count) chars; screens \(screens, privacy: .public)")
        }
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
