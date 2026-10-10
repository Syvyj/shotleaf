import AppKit
import Core
import SwiftUI

/// What the panel shows: the search, the type filter and the selected row.
@MainActor
@Observable
final class ClipboardPanelModel {
    let history: ClipboardHistory
    var query = "" { didSet { selected = 0 } }
    var kind: ClipItem.Kind? { didSet { selected = 0 } }
    var selected = 0

    init(history: ClipboardHistory) { self.history = history }

    var results: [ClipItem] { history.search(query, kind: kind) }
    var current: ClipItem? { let r = results; return r.indices.contains(selected) ? r[selected] : nil }

    static let kinds: [ClipItem.Kind?] = [nil, .text, .link, .image, .color, .file]

    func move(_ by: Int) {
        let count = results.count
        guard count > 0 else { return }
        selected = min(max(selected + by, 0), count - 1)
    }

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
    var openImage: (ImagePayload) -> Void = { _ in }
    private var panel: FloatingPanel?
    private var model: ClipboardPanelModel?
    private var monitor: Any?
    /// The app the user was in: the paste goes there, and only there.
    private var target: pid_t?

    init(history: ClipboardHistory) { self.history = history }

    var isShown: Bool { panel?.isVisible == true }

    func toggle() { isShown ? close() : show() }

    func show() {
        close()
        target = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let model = ClipboardPanelModel(history: history)
        self.model = model
        let view = ClipboardPanelView(model: model, pick: { [weak self] in self?.pick($0, $1) }, close: { [weak self] in self?.close() })
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
        switch Int(event.keyCode) {
        case 125: model.move(1); return true                                   // ↓
        case 126: model.move(-1); return true                                  // ↑
        case 48: model.nextKind(mods.contains(.shift) ? -1 : 1); return true   // Tab
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
            let results = model.results
            if results.indices.contains(n - 1) { pick(results[n - 1], .paste) }
            return true
        }
        return false
    }

    func pick(_ item: ClipItem, _ mode: Mode) {
        history.copy(item, plain: mode == .plain)
        close()
        // Paste only into the app the panel was opened over — never anywhere else.
        guard mode != .copy, let target, NSWorkspace.shared.frontmostApplication?.processIdentifier == target else {
            Sound.copied()
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(60)) // the panel's key status goes back to the app first
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target else { return }
            Self.pressCommandV()
        }
    }

    /// ⌘V as a real press: ⌘ down, V, ⌘ up — so ⌘ is never left held.
    static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for (key, down, flags) in [(55, true, CGEventFlags.maskCommand), (9, true, .maskCommand), (9, false, .maskCommand), (55, false, [])] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: 0x4150_494C) // APILA's own (the completion tap skips it)
            event.post(tap: .cghidEventTap)
        }
    }
}
