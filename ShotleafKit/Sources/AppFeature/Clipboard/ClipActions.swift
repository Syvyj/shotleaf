import Foundation

/// ⌘K in the clipboard panel: what can be done to a text entry before pasting.
enum ClipAction: CaseIterable, Identifiable {
    case cleanLinks, uppercase, lowercase, capitalize, oneLine, trim, formatJSON, saveSnippet

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
        case .saveSnippet: return text
        }
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
