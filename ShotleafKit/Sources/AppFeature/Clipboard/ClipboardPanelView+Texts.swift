import SwiftUI

/// What the panel says about an entry: its title, kind and details.
extension ClipboardPanelView {
    // MARK: Texts

    static func titleString(_ kind: ClipItem.Kind?) -> String.LocalizationValue {
        switch kind {
        case nil: "All"
        case .text?: "Text"
        case .link?: "Links"
        case .image?: "Images"
        case .color?: "Colors"
        case .file?: "Files"
        }
    }

    static func symbol(_ kind: ClipItem.Kind?) -> String {
        switch kind {
        case nil: "square.grid.2x2"
        case .text?: "text.alignleft"
        case .link?: "link"
        case .image?: "photo"
        case .color?: "paintpalette"
        case .file?: "doc"
        }
    }

    /// The row's text: the first non-empty line.
    static func line(_ item: ClipItem) -> String {
        switch item.kind {
        case .image:
            let size = item.imageSize.map { "\(Int($0.width))×\(Int($0.height))" } ?? ""
            let words = item.imageText?.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return [item.screenshot == true ? String(localized: "Screenshot") : String(localized: "Image"), size, words.isEmpty ? "" : "«\(words.prefix(40))»"].filter { !$0.isEmpty }.joined(separator: " · ")
        case .file: return item.fileURLs.map(\.lastPathComponent).joined(separator: ", ")
        default: return item.text.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? item.text
        }
    }

    static func meta(_ item: ClipItem) -> String {
        let ago = RelativeDateTimeFormatter()
        ago.unitsStyle = .short
        let when = Date().timeIntervalSince(item.date) < 60 ? String(localized: "now") : ago.localizedString(for: item.date, relativeTo: Date())
        return [item.appName, when].compactMap { $0 }.joined(separator: " · ")
    }

    static func details(_ item: ClipItem) -> String {
        let when = item.date.formatted(date: Calendar.current.isDateInToday(item.date) ? .omitted : .abbreviated, time: .shortened)
        let size = item.kind == .text || item.kind == .link ? String(localized: "\(item.text.count) characters") : nil
        return [item.appName, when, size].compactMap { $0 }.joined(separator: " · ")
    }

    static func color(_ hex: String) -> Color? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard let value = UInt32(digits.prefix(6), radix: 16) else { return nil }
        return Color(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
