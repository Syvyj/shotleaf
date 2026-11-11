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
    /// With `watch`, the text and pictures are handed out on request, so `watch` learns when an app reads them.
    static func put(_ text: String, images: [URL] = [], files: [URL] = [], on board: NSPasteboard = .general, watch: ReadWatch? = nil) {
        var objects: [NSPasteboardItem] = []
        func offer(_ item: NSPasteboardItem, _ data: Data, _ type: NSPasteboard.PasteboardType) {
            if let watch { watch.add(item, data, type) } else { item.setData(data, forType: type) }
        }
        if !text.isEmpty {
            let item = NSPasteboardItem()
            offer(item, Data(text.utf8), .string)
            objects.append(item)
        }
        if !images.isEmpty {
            let folder = TempFolder.paste.new()
            for (n, url) in images.enumerated() {
                guard let png = try? Data(contentsOf: url) else { continue }
                let file = folder.appendingPathComponent(String(localized: "Image") + " \(n + 1).png")
                try? png.write(to: file)
                let item = NSPasteboardItem()
                offer(item, png, .png)
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

/// Tells when another app has read what `Paster.put` offered (macOS asks the owner for
/// lazily offered data), so a temporary paste can be taken back as soon as it's used.
/// Reads before `armed` don't count: a clipboard tool may peek before ⌘V is pressed.
final class ReadWatch: NSObject, NSPasteboardItemDataProvider {
    private var data: [ObjectIdentifier: [NSPasteboard.PasteboardType: Data]] = [:]
    var armed = false
    private(set) var read = false

    fileprivate func add(_ item: NSPasteboardItem, _ bytes: Data, _ type: NSPasteboard.PasteboardType) {
        data[ObjectIdentifier(item), default: [:]][type] = bytes
        item.setDataProvider(self, forTypes: [type])
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if let bytes = data[ObjectIdentifier(item)]?[type] { item.setData(bytes, forType: type) }
        if armed { read = true }
    }

    /// Waits until an app read the paste after `armed`, or `limit` passes (an app that never reads).
    @MainActor
    func waitForRead(upTo limit: Duration) async {
        let end = ContinuousClock.now + limit
        while !read, ContinuousClock.now < end { try? await Task.sleep(for: .milliseconds(20)) }
        // An app reads a paste's types one after another: give it a moment to take the rest.
        if read { try? await Task.sleep(for: .milliseconds(150)) }
    }
}
