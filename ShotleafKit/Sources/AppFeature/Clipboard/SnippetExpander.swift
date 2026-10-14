import AppKit
import Carbon

/// Abbreviations: typing a snippet's abbreviation (e.g. ";addr") anywhere
/// replaces it with the snippet. Listens to key presses in other apps (needs
/// Accessibility, which completion already has); secure fields never reach it.
/// The paste goes through the clipboard, which is put back right after.
@MainActor
final class SnippetExpander {
    let store: SnippetStore
    /// A snippet with {?questions}: the panel asks them.
    var ask: (Snippet) -> Void = { _ in }
    private var typed = ""
    /// The same keys read on the Latin layout: "mail" typed with Ukrainian on
    /// still matches (it comes out as "ьфшд" in `typed`).
    private var keys = ""
    private var monitors: [Any] = []

    init(store: SnippetStore) { self.store = store }

    func start() {
        guard monitors.isEmpty else { return }
        if let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.key(event) }
        }) { monitors.append(keys) }
        if let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.reset() } // the caret may have moved
        }) { monitors.append(clicks) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        reset()
    }

    private func key(_ event: NSEvent) {
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == Paster.marker { return } // our own keys
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        switch Int(event.keyCode) {
        case 51: typed = String(typed.dropLast()); keys = String(keys.dropLast()); return // ⌫
        case 36, 76, 48, 53, 123, 124, 125, 126, 115, 116, 119, 121: reset(); return // ↩ Tab esc arrows Home/End/PgUp/PgDn
        default: break
        }
        guard mods.subtracting(.option).isEmpty, let chars = event.characters, !chars.isEmpty else { reset(); return }
        typed = String((typed + chars).suffix(64))
        keys = String((keys + (Self.latin(event) ?? chars)).suffix(64))
        guard let snippet = Self.match(typed, in: store.snippets) ?? Self.match(keys, in: store.snippets) else { return }
        reset()
        expand(snippet)
    }

    private func reset() { typed = ""; keys = "" }

    /// What the key types on the Latin (ASCII-capable) layout the user has.
    private static func latin(_ event: NSEvent) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layout = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        let shift: UInt32 = event.modifierFlags.contains(.shift) ? UInt32(shiftKey >> 8) : 0
        var dead: UInt32 = 0, length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = layout.withUnsafeBytes { bytes in
            UCKeyTranslate(bytes.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self), event.keyCode,
                           UInt16(kUCKeyActionDown), shift, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
        }
        return status == noErr && length > 0 ? String(utf16CodeUnits: chars, count: length) : nil
    }

    /// The snippet whose abbreviation the typing ends with (the longest wins).
    /// One that starts with a letter ("mail") counts only as a whole word, so
    /// typing "gmail" doesn't set it off; ";mail" style ones work anywhere.
    static func match(_ typed: String, in snippets: [Snippet]) -> Snippet? {
        snippets.filter { snippet in
            let abbr = snippet.abbreviation
            guard !abbr.isEmpty, typed.hasSuffix(abbr) else { return false }
            guard abbr.first?.isLetter == true || abbr.first?.isNumber == true else { return true }
            let before = typed.dropLast(abbr.count).last
            return before.map { !$0.isLetter && !$0.isNumber } ?? true
        }
        .max { $0.abbreviation.count < $1.abbreviation.count }
    }

    private func expand(_ snippet: Snippet) {
        let saved = Paster.snapshot()
        let filled = SnippetText.expand(snippet.text, clipboard: NSPasteboard.general.string(forType: .string) ?? "")
        let asks = !SnippetText.questions(in: snippet.text).isEmpty
        Task {
            // We see the abbreviation's last key before the app has typed it: let it land, then erase.
            try? await Task.sleep(for: .milliseconds(50))
            await Paster.pressDelete(snippet.abbreviation.count)
            if asks { ask(snippet); return }
            Paster.put(filled.text, images: store.imageURLs(snippet))
            try? await Task.sleep(for: .milliseconds(40))
            Paster.pressCommandV()
            if filled.afterCursor > 0 {
                try? await Task.sleep(for: .milliseconds(120))
                Paster.pressLeft(filled.afterCursor)
            }
            try? await Task.sleep(for: .milliseconds(400)) // the app has read the clipboard by now
            Paster.restore(saved)
        }
    }
}
