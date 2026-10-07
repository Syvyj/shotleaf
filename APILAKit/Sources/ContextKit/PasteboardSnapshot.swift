import AppKit

/// A full copy of the general pasteboard — every item, every type (images, files,
/// rich text), not just the plain string — so APILA can put the user's clipboard
/// back exactly as it was after borrowing it for ⌘C / ⌘V.
public struct PasteboardSnapshot: Sendable {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    @MainActor
    public init(_ pasteboard: NSPasteboard = .general) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var types: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { types[type] = data }
            }
            return types
        }
    }

    @MainActor
    public func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.writeObjects(items.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        })
    }
}
