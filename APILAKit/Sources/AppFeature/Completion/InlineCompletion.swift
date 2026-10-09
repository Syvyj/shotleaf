import AppKit
import ApplicationServices
import EmbeddedKit
import OSLog

/// System-wide inline completion (Cotypist-style): while you type in any app,
/// the built-in model suggests how the line goes on, shown as grey "ghost"
/// text right after the cursor. Tab accepts the next word (⌥Tab — all of it),
/// typing the same letters keeps it, anything else or Esc drops it.
///
/// How: a keyboard event tap (needs Accessibility) watches keys and catches
/// Tab while a suggestion is up; the focused field's text and caret come from
/// the Accessibility API; accepted text is typed as synthetic key events.
/// Runs only on the built-in model — your text never leaves the Mac.
/// ponytail: suggests only at the end of a line, no app-specific fixes yet.
@MainActor
final class InlineCompletion {
    private let log = Logger(subsystem: "app.apila.APILA", category: "completion")
    /// Marks APILA's own synthetic key events so the tap lets them through.
    private static let marker: Int64 = 0x4150_494C // "APIL"
    private static let debounce: Duration = .milliseconds(320)

    /// Apps where completion only gets in the way.
    private static let excluded: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty",
        "com.mitchellh.ghostty", "io.alacritty", "com.apple.keychainaccess", "com.1password.1password",
    ]
    /// Chromium browsers expose their text to Accessibility only on request.
    private static let chromium: Set<String> = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    private var tap: CFMachPort?
    private var debounceTask: Task<Void, Never>?
    private var generation: Task<Void, Never>?
    private let ghost = GhostPanel()
    /// What's on screen now, and where it belongs.
    private var suggestion: String?
    private var field: FocusedField?
    private var activationObserver: NSObjectProtocol?

    var isRunning: Bool { tap != nil }

    /// Starts watching. False when macOS refuses the event tap (no Accessibility).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask), callback: inlineCompletionTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log.error("event tap refused — Accessibility off?")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
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
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
    }

    // MARK: Keys

    /// Returns true to swallow the event.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type == .keyDown else { dismiss(); return false } // a click moves the caret
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker { return false }

        let key = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        if let suggestion {
            if key == 48, flags.isDisjoint(with: [.maskCommand, .maskControl, .maskShift]) { // Tab
                accept(flags.contains(.maskAlternate) ? suggestion : CompletionText.nextWord(of: suggestion).word)
                return true
            }
            if key == 53 { dismiss(); return true } // Esc
        }
        if !flags.isDisjoint(with: [.maskCommand, .maskControl]) {
            dismiss()
            return false
        }
        // Typing the suggested letters keeps the rest of the suggestion.
        let typed = Self.characters(of: event)
        if let suggestion, let rest = CompletionText.advance(suggestion, typed: typed) {
            self.suggestion = rest
            ghost.update(text: rest)
            reposition(after: .milliseconds(30))
        } else {
            hide()
        }
        schedule()
        return false
    }

    private static func characters(of event: CGEvent) -> String {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &chars)
        return String(utf16CodeUnits: chars, count: length)
    }

    // MARK: Suggest

    private func schedule() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            self?.suggest()
        }
    }

    private func suggest() {
        guard EmbeddedModel.isDownloaded, let field = FocusedField.current(excluding: Self.excluded) else { return }
        guard CompletionText.shouldComplete(beforeCursor: field.beforeCursor) else { return }
        generation?.cancel()
        let prompt = CompletionText.prompt(beforeCursor: field.beforeCursor)
        generation = Task { [weak self] in
            do {
                let started = ContinuousClock.now
                let raw = try await EmbeddedModel.shared.complete(prompt)
                guard !Task.isCancelled, let self else { return }
                // Still the same field and text? Otherwise the user moved on.
                guard let now = FocusedField.current(excluding: Self.excluded), now.beforeCursor == field.beforeCursor,
                      let text = CompletionText.fromEcho(raw, beforeCursor: field.beforeCursor)
                else { return }
                self.log.debug("suggestion in \(ContinuousClock.now - started, privacy: .public): \(raw, privacy: .private)")
                // Only what fits before the field's right edge.
                guard let visible = GhostPanel.fitting(text, caret: now.caret, rightEdge: now.rightEdge) else { return }
                self.show(visible, in: now)
            } catch {
                self?.log.error("completion failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func show(_ text: String, in field: FocusedField) {
        suggestion = text
        self.field = field
        ghost.show(text: text, caret: field.caret)
    }

    private func reposition(after delay: Duration) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.suggestion != nil, let field = FocusedField.current(excluding: Self.excluded) else { return }
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

/// C callback → the controller (the tap runs on the main run loop).
private func inlineCompletionTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<InlineCompletion>.fromOpaque(refcon).takeUnretainedValue()
    nonisolated(unsafe) let shared = event // used on the main thread only, synchronously
    let swallow = MainActor.assumeIsolated { controller.handle(type, shared) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

/// The text field that has the keyboard, read through Accessibility.
struct FocusedField {
    let element: AXUIElement
    let beforeCursor: String
    /// The character before the caret, in AppKit screen coordinates.
    let caret: CGRect
    /// The field's right edge (screen x): suggestions stop there.
    let rightEdge: CGFloat

    /// nil when there's no editable, non-secure field with an empty selection
    /// at the end of a line (or the app is excluded / APILA itself).
    static func current(excluding excluded: Set<String>) -> FocusedField? {
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
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let caret = CGRect(x: bounds.minX, y: top - bounds.maxY, width: bounds.width, height: bounds.height)
        var rightEdge = caret.maxX + 600
        if let position: AXValue = attribute(element, kAXPositionAttribute), let size: AXValue = attribute(element, kAXSizeAttribute) {
            var origin = CGPoint.zero, extent = CGSize.zero
            if AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &extent), extent.width > 0 {
                rightEdge = origin.x + extent.width
            }
        }
        return FocusedField(element: element, beforeCursor: text.substring(to: range.location), caret: caret, rightEdge: rightEdge)
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
