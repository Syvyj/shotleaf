import AppKit
import Core
import SwiftUI

/// What the panel shows: the search, the type filter and the selected row.
@MainActor
@Observable
final class ClipboardPanelModel {
    let history: ClipboardHistory
    let snippets: SnippetStore
    var query = "" { didSet { selected = 0 } }
    var kind: ClipItem.Kind? { didSet { selected = 0 } }
    /// The Snippets tab instead of the history.
    var showsSnippets = false { didSet { selected = 0; asking = nil } }
    var selected = 0
    /// A snippet with {?questions}, waiting for the answers.
    var asking: Snippet?
    var answers: [String: String] = [:]

    init(history: ClipboardHistory, snippets: SnippetStore) {
        self.history = history
        self.snippets = snippets
    }

    var results: [ClipItem] { history.search(query, kind: kind) }
    var current: ClipItem? { guard !showsSnippets else { return nil }; let r = results; return r.indices.contains(selected) ? r[selected] : nil }
    var snippetResults: [Snippet] { snippets.search(query) }
    var currentSnippet: Snippet? { guard showsSnippets else { return nil }; let r = snippetResults; return r.indices.contains(selected) ? r[selected] : nil }
    var count: Int { showsSnippets ? snippetResults.count : results.count }

    static let kinds: [ClipItem.Kind?] = [nil, .text, .link, .image, .color, .file]

    func move(_ by: Int) {
        guard count > 0 else { selected = 0; return }
        selected = min(max(selected + by, 0), count - 1)
    }

    /// ⇧Tab: the history's types, round and round.
    func nextKind(_ by: Int) {
        let i = Self.kinds.firstIndex(of: kind) ?? 0
        kind = Self.kinds[(i + by + Self.kinds.count) % Self.kinds.count]
    }
}

/// ⇧⌘V: the clipboard history in a panel by the mouse pointer. It takes the
/// keyboard without activating APILA, so the app being typed in stays in
/// front; picking an entry puts it on the clipboard and presses ⌘V there.
@MainActor
final class ClipboardPanelController {
    enum Mode { case paste, plain, copy }

    let history: ClipboardHistory
    let snippets: SnippetStore
    var openImage: (ImagePayload) -> Void = { _ in }
    var openSnippetEditor: () -> Void = {}
    private var panel: FloatingPanel?
    private var model: ClipboardPanelModel?
    private var monitor: Any?
    /// The app the user was in: the paste goes there, and only there.
    private var target: pid_t?

    init(history: ClipboardHistory, snippets: SnippetStore) {
        self.history = history
        self.snippets = snippets
    }

    var isShown: Bool { panel?.isVisible == true }

    func toggle(snippets: Bool = false) { isShown ? close() : show(snippets: snippets) }

    func show(snippets showsSnippets: Bool = false, asking: Snippet? = nil) {
        close()
        target = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let model = ClipboardPanelModel(history: history, snippets: snippets)
        model.showsSnippets = showsSnippets
        model.asking = asking
        self.model = model
        let view = ClipboardPanelView(model: model, pick: { [weak self] in self?.pick($0, $1) },
                                      pickSnippet: { [weak self] in self?.pick($0, $1) },
                                      editSnippets: { [weak self] in self?.close(); self?.openSnippetEditor() },
                                      close: { [weak self] in self?.close() })
        let panel = ScreenshotWindows.makePanel(view)
        panel.setFrameOrigin(Self.origin(for: panel.frame.size))
        self.panel = panel
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handle(event) ? nil : event
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }

    /// By the mouse pointer, like a menu (below-right of it); always on screen.
    static func origin(for size: CGSize, at mouse: CGPoint = NSEvent.mouseLocation) -> CGPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = CGPoint(x: mouse.x - 24, y: mouse.y - size.height - 8)
        if origin.y < visible.minY { origin.y = mouse.y + 8 } // no room below: above the pointer
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        return origin
    }

    /// Keys the panel answers before the search field sees them.
    private func handle(_ event: NSEvent) -> Bool {
        guard let model else { return false }
        let mods = event.modifierFlags.intersection([.command, .option, .shift, .control])
        if let snippet = model.asking { // the questions' fields have the keyboard
            switch Int(event.keyCode) {
            case 36, 76: finish(snippet, answers: model.answers, mods.contains(.command) ? .copy : .paste); return true
            case 53: model.asking = nil; return true
            default: return false
            }
        }
        if model.showsSnippets, Int(event.keyCode) != 48 {
            switch Int(event.keyCode) {
            case 36, 76:
                if let snippet = model.currentSnippet { pick(snippet, mods.contains(.command) ? .copy : .paste) }
                return true
            case 51 where mods == .command: return true
            default: break
            }
            if mods == .command, ["p", "e"].contains(event.charactersIgnoringModifiers?.lowercased() ?? "") { return true }
        }
        switch Int(event.keyCode) {
        case 125: model.move(1); return true                                   // ↓
        case 126: model.move(-1); return true                                  // ↑
        case 48:                                                               // Tab: history ↔ snippets, ⇧Tab: the types
            if mods.contains(.shift) { model.showsSnippets = false; model.nextKind(1) } else { model.showsSnippets.toggle() }
            return true
        case 53: close(); return true                                          // esc
        case 36, 76:                                                           // ↩
            guard let item = model.current else { return true }
            pick(item, mods.contains(.command) ? .copy : mods.contains(.option) ? .plain : .paste)
            return true
        case 51 where mods == .command:                                        // ⌘⌫
            if let item = model.current { history.remove(item.id); model.move(0) }
            return true
        default: break
        }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if mods == .command, key == "p", let item = model.current { history.togglePin(item.id); return true }
        if mods == .command, key == "e", let item = model.current, item.hasImage,
           let data = try? Data(contentsOf: history.imageURL(item)), let payload = ScreenshotWindows.payload(fromImageData: data) {
            close()
            openImage(payload)
            return true
        }
        // 1–9 paste that row: always with ⌘, and bare while the search is empty.
        if let n = Int(key), (1...9).contains(n), mods == .command || (mods.isEmpty && model.query.isEmpty) {
            if model.showsSnippets {
                let results = model.snippetResults
                if results.indices.contains(n - 1) { pick(results[n - 1], .paste) }
            } else {
                let results = model.results
                if results.indices.contains(n - 1) { pick(results[n - 1], .paste) }
            }
            return true
        }
        return false
    }

    /// A snippet: its questions first (in the panel), then the filled-in text.
    func pick(_ snippet: Snippet, _ mode: Mode) {
        if !SnippetText.questions(in: snippet.text).isEmpty, model?.asking == nil {
            if model == nil { show(snippets: true, asking: snippet) } else { model?.answers = [:]; model?.asking = snippet }
            return
        }
        finish(snippet, answers: model?.answers ?? [:], mode)
    }

    private func finish(_ snippet: Snippet, answers: [String: String], _ mode: Mode) {
        let filled = SnippetText.expand(snippet.text, answers: answers, clipboard: NSPasteboard.general.string(forType: .string) ?? "")
        Paster.put(filled.text)
        close()
        pasteIntoTarget(mode, thenLeft: filled.afterCursor)
    }

    func pick(_ item: ClipItem, _ mode: Mode) {
        history.copy(item, plain: mode == .plain)
        close()
        pasteIntoTarget(mode)
    }

    private func pasteIntoTarget(_ mode: Mode, thenLeft left: Int = 0) {
        // Paste only into the app the panel was opened over — never anywhere else.
        guard mode != .copy, let target, NSWorkspace.shared.frontmostApplication?.processIdentifier == target else {
            Sound.copied()
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(60)) // the panel's key status goes back to the app first
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target else { return }
            Paster.pressCommandV()
            if left > 0 { // the caret to the snippet's {cursor}
                try? await Task.sleep(for: .milliseconds(120))
                Paster.pressLeft(left)
            }
        }
    }
}

/// Puts text on the clipboard and presses keys in the app in front — always as
/// APILA's own events (the completion tap and the history skip them), with
/// modifiers released.
@MainActor
enum Paster {
    static let marker: Int64 = 0x4150_494C

    /// Text on the clipboard, marked as APILA's so the history doesn't keep it.
    static func put(_ text: String, on board: NSPasteboard = .general) {
        board.clearContents()
        board.setString(text, forType: .string)
        board.setData(Data(), forType: ClipboardHistory.ownType)
    }

    /// ⌘V as a real press: ⌘ down, V, ⌘ up — so ⌘ is never left held.
    static func pressCommandV() {
        press([(55, true, .maskCommand), (9, true, .maskCommand), (9, false, .maskCommand), (55, false, [])])
    }

    /// ← `count` times (to put the caret at a snippet's {cursor}).
    static func pressLeft(_ count: Int) {
        press(Array(repeating: [(123, true, CGEventFlags()), (123, false, CGEventFlags())], count: count).flatMap { $0 })
    }

    /// ⌫ `count` times (to remove a typed abbreviation).
    static func pressDelete(_ count: Int) {
        press(Array(repeating: [(51, true, CGEventFlags()), (51, false, CGEventFlags())], count: count).flatMap { $0 })
    }

    private static func press(_ keys: [(Int, Bool, CGEventFlags)]) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for (key, down, flags) in keys {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cghidEventTap)
        }
    }

    /// Everything on the clipboard, to put back after a temporary paste.
    static func snapshot(_ board: NSPasteboard = .general) -> [[NSPasteboard.PasteboardType: Data]] {
        (board.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    static func restore(_ saved: [[NSPasteboard.PasteboardType: Data]], to board: NSPasteboard = .general) {
        board.clearContents()
        let items = saved.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            item.setData(Data(), forType: ClipboardHistory.ownType)
            return item
        }
        board.writeObjects(items)
    }
}
