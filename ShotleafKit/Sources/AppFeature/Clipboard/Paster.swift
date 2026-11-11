import AppKit
import Core
import SwiftUI

/// Puts text on the clipboard and presses keys in the app in front — always as
/// Shotleaf's own events (the completion tap and the history skip them), with
/// modifiers released.
@MainActor
enum Paster {
    /// On every key event Shotleaf posts (pastes, snippets, completions), so its own taps skip them.
    nonisolated static let marker: Int64 = 0x4150_494C // "APIL"

    /// Text on the clipboard, marked as Shotleaf's so the history doesn't keep it.
    /// With pictures or files, each is its own pasteboard item — a picture as PNG
    /// plus a named file — so apps that take several get them all.
    static func put(_ text: String, images: [URL] = [], files: [URL] = [], on board: NSPasteboard = .general) {
        var objects: [NSPasteboardItem] = []
        if !text.isEmpty {
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            objects.append(item)
        }
        if !images.isEmpty {
            let folder = TempFolder.paste.new()
            for (n, url) in images.enumerated() {
                guard let png = try? Data(contentsOf: url) else { continue }
                let file = folder.appendingPathComponent(String(localized: "Image") + " \(n + 1).png")
                try? png.write(to: file)
                let item = NSPasteboardItem()
                item.setData(png, forType: .png)
                item.setString(file.absoluteString, forType: .fileURL)
                objects.append(item)
            }
        }
        for url in files {
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            objects.append(item)
        }
        objects.forEach { $0.setData(Data(), forType: ClipboardHistory.ownType) }
        board.clearContents()
        board.writeObjects(objects)
    }

    /// ⌘V as a real press: ⌘ down, V, ⌘ up — so ⌘ is never left held.
    static func pressCommandV() {
        press([(55, true, .maskCommand), (9, true, .maskCommand), (9, false, .maskCommand), (55, false, [])])
    }

    /// ← `count` times (to put the caret at a snippet's {cursor}).
    static func pressLeft(_ count: Int) {
        press(Array(repeating: [(123, true, CGEventFlags()), (123, false, CGEventFlags())], count: count).flatMap { $0 })
    }

    /// ⌫ `count` times (to remove a typed abbreviation), one at a time: some apps
    /// drop keys that arrive all at once, which left the abbreviation's first character behind.
    static func pressDelete(_ count: Int) async {
        for _ in 0..<count {
            press([(51, true, CGEventFlags()), (51, false, CGEventFlags())])
            try? await Task.sleep(for: .milliseconds(8))
        }
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
