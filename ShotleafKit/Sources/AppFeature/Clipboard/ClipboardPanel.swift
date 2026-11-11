import AppKit
import Core
import SwiftUI

/// What the panel shows: the search, the type filter and the selected row.
@MainActor
@Observable
final class ClipboardPanelModel {
    let history: ClipboardHistory
    let snippets: SnippetStore
    var query = "" { didSet { selected = 0; actionsShown = false } }
    var kind: ClipItem.Kind? { didSet { selected = 0 } }
    /// The Snippets tab instead of the history.
    var showsSnippets = false { didSet { selected = 0; asking = nil } }
    var selected = 0
    /// Entries picked with ⌘-click / ⇧↑↓, in the order picked.
    var marked: [UUID] = []
    /// ⌘K: the actions list instead of the preview.
    var actionsShown = false { didSet { actionIndex = 0 } }
    var actionIndex = 0
    var actions: [ClipAction] {
        guard let item = current else { return [] }
        if marked.count > 1 || item.kind == .image { return [.saveSnippet] } // pictures and several: into a snippet
        guard item.kind != .file else { return [] }
        return ClipAction.available(for: item.text)
    }
    /// A snippet with {?questions}, waiting for the answers.
    var asking: Snippet?
    var answers: [String: String] = [:]

    init(history: ClipboardHistory, snippets: SnippetStore) {
        self.history = history
        self.snippets = snippets
    }

    var results: [ClipItem] { history.search(query, kind: kind) }
    var current: ClipItem? { guard !showsSnippets else { return nil }; let r = results; return r.indices.contains(selected) ? r[selected] : nil }
    /// The folder on the Snippets tab (nil = all); remembered for next time.
    nonisolated static let folderKey = "snippetFolder"
    var snippetFolder: UUID? = UserDefaults.standard.string(forKey: ClipboardPanelModel.folderKey).flatMap(UUID.init) {
        didSet { selected = 0; UserDefaults.standard.set(snippetFolder?.uuidString, forKey: Self.folderKey) }
    }
    /// The folder's snippets; a search looks through all of them.
    var snippetResults: [Snippet] {
        let found = snippets.search(query)
        guard query.isEmpty, let folder = snippetFolder, snippets.folder(folder) != nil else { return found }
        return found.filter { $0.folder == folder }
    }

    /// ← →: the previous / next folder ("All" first).
    func nextFolder(_ by: Int) {
        let all: [UUID?] = [nil] + snippets.folders.map(\.id)
        let i = all.firstIndex(of: snippetFolder) ?? 0
        snippetFolder = all[min(max(i + by, 0), all.count - 1)]
    }
    var currentSnippet: Snippet? { guard showsSnippets else { return nil }; let r = snippetResults; return r.indices.contains(selected) ? r[selected] : nil }
    var count: Int { showsSnippets ? snippetResults.count : results.count }

    static let kinds: [ClipItem.Kind?] = [nil, .text, .link, .image, .color, .file]

    func move(_ by: Int) {
        actionsShown = false
        guard count > 0 else { selected = 0; return }
        selected = min(max(selected + by, 0), count - 1)
    }

    func toggleMark(_ id: UUID) {
        if let i = marked.firstIndex(of: id) { marked.remove(at: i) } else { marked.append(id) }
    }

    /// ⇧↑ / ⇧↓: take the current entry and the next one into the selection.
    func extendMark(_ by: Int) {
        if let id = current?.id, !marked.contains(id) { marked.append(id) }
        move(by)
        if let id = current?.id, !marked.contains(id) { marked.append(id) }
    }

    var markedItems: [ClipItem] { marked.compactMap { id in history.items.first { $0.id == id } } }
    /// The picked entries when `item` is one of several picked, else just `item`.
    func entries(with item: ClipItem) -> [ClipItem] { marked.count > 1 && marked.contains(item.id) ? markedItems : [item] }
    /// The entry being dragged out of the list (to a snippets folder).
    var dragged: ClipItem?

    /// ⇧Tab: the history's types, round and round.
    func nextKind(_ by: Int) {
        let i = Self.kinds.firstIndex(of: kind) ?? 0
        kind = Self.kinds[(i + by + Self.kinds.count) % Self.kinds.count]
    }
}

/// ⇧⌘V: the clipboard history in a panel by the mouse pointer. It takes the
/// keyboard without activating Shotleaf, so the app being typed in stays in
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
                                      pickTogether: { [weak self] in self?.pasteTogether($0) },
                                      pickQueue: { [weak self] in self?.startQueue($0) },
                                      runAction: { [weak self] in self?.run($0) },
                                      saveSnippet: { [weak self] in self?.saveSnippet($0, folder: $1) },
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
        if model.actionsShown {
            let actions = model.actions
            switch Int(event.keyCode) {
            case 125: model.actionIndex = min(model.actionIndex + 1, max(actions.count - 1, 0)); return true
            case 126: model.actionIndex = max(model.actionIndex - 1, 0); return true
            case 36, 76: if actions.indices.contains(model.actionIndex) { run(actions[model.actionIndex]) }; return true
            case 53: model.actionsShown = false; return true
            default:
                if let n = Int(event.charactersIgnoringModifiers ?? ""), actions.indices.contains(n - 1) { run(actions[n - 1]); return true }
                if mods == .command, event.charactersIgnoringModifiers?.lowercased() == "k" { model.actionsShown = false; return true }
                return false
            }
        }
        if !model.showsSnippets {
            switch Int(event.keyCode) {
            case 125 where mods == .shift: model.extendMark(1); return true
            case 126 where mods == .shift: model.extendMark(-1); return true
            case 53 where !model.marked.isEmpty: model.marked = []; return true
            case 36 where model.marked.count > 1, 76 where model.marked.count > 1: // `where` binds to one pattern only
                if mods.contains(.command) { startQueue(model.markedItems) } else { pasteTogether(model.markedItems) }
                return true
            default: break
            }
            if mods == .command, event.charactersIgnoringModifiers?.lowercased() == "k", !model.actions.isEmpty {
                model.actionsShown = true
                return true
            }
        }
        if model.showsSnippets, Int(event.keyCode) != 48 {
            switch Int(event.keyCode) {
            case 36, 76:
                if let snippet = model.currentSnippet { pick(snippet, mods.contains(.command) ? .copy : .paste) }
                return true
            case 51 where mods == .command: return true
            case 123 where model.query.isEmpty: model.nextFolder(-1); return true // ←
            case 124 where model.query.isEmpty: model.nextFolder(1); return true  // →
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
        // ⌘1–⌘9 paste that row; bare digits are typed into the search.
        if let n = Int(key), (1...9).contains(n), mods == .command {
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
        Paster.put(filled.text, images: snippets.imageURLs(snippet))
        close()
        pasteIntoTarget(mode, thenLeft: filled.afterCursor)
    }

    // MARK: Several entries, actions

    /// The picked entries as one text, a line each (pictures left out).
    func pasteTogether(_ items: [ClipItem]) {
        guard !items.isEmpty else { return }
        history.copyTogether(items)
        close()
        pasteIntoTarget(.paste)
    }

    /// Pastes the first now; then each ⇧⌘V pastes the next one.
    func startQueue(_ items: [ClipItem]) {
        history.queue = items.map(\.id)
        history.queueTotal = items.count
        close()
        pasteNextQueued()
    }

    var isQueueing: Bool { !history.queue.isEmpty }

    func pasteNextQueued() {
        guard let id = history.queue.first else { return }
        history.queue.removeFirst()
        guard let item = history.items.first(where: { $0.id == id }) else { pasteNextQueued(); return }
        target = NSWorkspace.shared.frontmostApplication?.processIdentifier
        history.copy(item)
        pasteIntoTarget(.paste)
        let done = history.queueTotal - history.queue.count
        Toast.show(history.queue.isEmpty ? String(localized: "Queue done: \(done) of \(history.queueTotal)")
                                         : String(localized: "Pasted \(done) of \(history.queueTotal) · ⇧⌘V — the next one"))
    }

    func cancelQueue() {
        history.queue = []
    }

    fileprivate func run(_ action: ClipAction) {
        guard let model, let item = model.current else { return }
        if action == .saveSnippet {
            // The picked entries (or the current one) become one snippet, in the folder last opened.
            saveSnippet(model.entries(with: item), folder: model.snippetFolder)
            model.actionsShown = false
            return
        }
        guard let text = action.apply(item.text) else { return }
        Paster.put(text)
        close()
        pasteIntoTarget(.paste)
    }

    /// Entries as one snippet: their texts and pictures.
    fileprivate func saveSnippet(_ entries: [ClipItem], folder: UUID?) {
        guard !entries.isEmpty else { return }
        let text = entries.filter { $0.kind != .image }.map(\.text).joined(separator: "\n")
        let pngs = entries.filter { $0.kind == .image }.compactMap { try? Data(contentsOf: history.imageURL($0)) }
        let title = text.split(whereSeparator: \.isNewline).first.map { String($0.prefix(40)) }
            ?? (pngs.count > 1 ? String(localized: "Screenshots (\(pngs.count))") : String(localized: "Screenshot"))
        let saved = snippets.save(title: title, text: text, pngs: pngs, folder: folder)
        model?.marked = []
        Toast.show(snippets.folder(saved.folder).map { String(localized: "Saved to “\($0.name)”") } ?? String(localized: "Saved as a snippet"))
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
