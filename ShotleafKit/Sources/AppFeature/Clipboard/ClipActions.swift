import Foundation

/// ⌘K on a picture: paste it as a small JPEG.
enum ImageClipAction: Hashable {
    case compress(limit: Int)

    var title: String.LocalizationValue {
        switch self {
        case .compress(let limit): "Compress to JPEG under \(SmallFile.label(limit))"
        }
    }

    var symbol: String { "arrow.down.right.and.arrow.up.left" }

    /// Every limit, the last chosen one first.
    static func all(remembered: Int) -> [ImageClipAction] {
        let first = SmallFile.chosen(remembered)
        return ([first] + SmallFile.limits.filter { $0 != first }).map { .compress(limit: $0) }
    }
}

/// A row of the ⌘K list.
enum PanelAction: Hashable {
    case text(ClipAction), image(ImageClipAction)

    var title: String.LocalizationValue {
        switch self { case .text(let a): a.title; case .image(let a): a.title }
    }
    var symbol: String {
        switch self { case .text(let a): a.symbol; case .image(let a): a.symbol }
    }
}

/// ⌘K in the clipboard panel: what can be done to a text entry before pasting.
enum ClipAction: CaseIterable, Identifiable {
    case cleanLinks, uppercase, lowercase, capitalize, oneLine, trim, formatJSON, convertColor, decodeBase64, encodeBase64, saveSnippet

    var id: Self { self }

    var title: String.LocalizationValue {
        switch self {
        case .cleanLinks: "Clean links of trackers"
        case .uppercase: "UPPERCASE"
        case .lowercase: "lowercase"
        case .capitalize: "Capitalize Words"
        case .oneLine: "Join into one line"
        case .trim: "Trim spaces"
        case .formatJSON: "Format JSON"
        case .convertColor: "Convert color (HEX ↔ RGB)"
        case .decodeBase64: "Decode Base64"
        case .encodeBase64: "Encode Base64"
        case .saveSnippet: "Save as snippet"
        }
    }

    var symbol: String {
        switch self {
        case .cleanLinks: "link.badge.plus"
        case .uppercase: "textformat.size.larger"
        case .lowercase: "textformat.size.smaller"
        case .capitalize: "textformat"
        case .oneLine: "arrow.right.to.line"
        case .trim: "scissors"
        case .formatJSON: "curlybraces"
        case .convertColor: "paintpalette"
        case .decodeBase64: "lock.open"
        case .encodeBase64: "lock"
        case .saveSnippet: "text.badge.star"
        }
    }

    /// The actions that would change `text` (saving as a snippet always can).
    static func available(for text: String) -> [ClipAction] {
        allCases.filter { $0 == .saveSnippet || ($0.apply(text).map { $0 != text } ?? false) }
    }

    /// The changed text; nil when it doesn't apply (e.g. not JSON).
    func apply(_ text: String) -> String? {
        switch self {
        case .cleanLinks: return Self.cleanLinks(text)
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        case .capitalize: return text.capitalized
        case .oneLine:
            return text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: " ")
        case .trim:
            return text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.replacing(/[ \t]+/, with: " ").trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        case .formatJSON:
            guard let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data),
                  let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            else { return nil }
            return String(data: pretty, encoding: .utf8)
        case .convertColor: return Self.convertColor(text)
        case .decodeBase64:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 8, let data = Data(base64Encoded: trimmed), let decoded = String(data: data, encoding: .utf8),
                  !decoded.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && !"\n\r\t".unicodeScalars.contains($0) })
            else { return nil }
            return decoded
        case .encodeBase64: return Data(text.utf8).base64EncodedString()
        case .saveSnippet: return text
        }
    }

    /// "#1A2B3C" (or "1a2b3c", "#abc") ↔ "rgb(26, 43, 60)"; nil for anything else.
    static func convertColor(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Without "#" only six hex digits with a number among them: "decade" or "bad" stay words.
        if let m = t.wholeMatch(of: /(?i)#([0-9a-f]{3}|[0-9a-f]{6})|(?=[a-f]*\d)([0-9a-f]{6})/) {
            var hex = String(m.1 ?? m.2 ?? "")
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard let v = Int(hex, radix: 16) else { return nil }
            return "rgb(\(v >> 16), \(v >> 8 & 0xFF), \(v & 0xFF))"
        }
        if let m = t.wholeMatch(of: /(?i)rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(?:,\s*[\d.]+\s*)?\)/),
           let r = Int(m.1), let g = Int(m.2), let b = Int(m.3), [r, g, b].allSatisfy({ $0 <= 255 }) {
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        return nil
    }

    /// Tracking parameters people never mean to share.
    static let trackers: Set<String> = ["fbclid", "gclid", "dclid", "msclkid", "yclid", "mc_cid", "mc_eid", "igshid", "si",
                                        "_hsenc", "_hsmi", "ref_src", "spm", "vero_id", "oly_enc_id", "oly_anon_id", "wickedid"]

    /// Every http(s) link in `text` without utm_* and the like.
    static func cleanLinks(_ text: String) -> String {
        text.replacing(/https?:\/\/[^\s<>"']+/) { match in
            let link = String(match.output)
            guard var parts = URLComponents(string: link), let items = parts.queryItems else { return link }
            let kept = items.filter { !$0.name.lowercased().hasPrefix("utm_") && !trackers.contains($0.name.lowercased()) }
            guard kept.count != items.count else { return link }
            parts.queryItems = kept.isEmpty ? nil : kept
            return parts.string ?? link
        }
    }
}
