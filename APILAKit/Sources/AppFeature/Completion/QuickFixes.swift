import AppKit
import NaturalLanguage

/// What can be offered at the cursor besides a continuation: an emoji for a
/// `:shortcode` and a fix for the word just typed. Both replace text before
/// the cursor, so they say how much.
enum QuickFix: Equatable {
    /// `:roc` → 🚀 (`name` is shown next to it).
    case emoji(String, name: String, replacing: Int)
    /// "helo " → "hello ".
    case typo(String, replacing: Int)

    /// Text to type after deleting `replacing` characters.
    var insert: String {
        switch self {
        case .emoji(let emoji, _, _): emoji
        case .typo(let fix, _): fix
        }
    }

    var replacing: Int {
        switch self {
        case .emoji(_, _, let n), .typo(_, let n): n
        }
    }

    /// What the badge says.
    var label: String {
        switch self {
        case .emoji(let emoji, let name, _): "\(emoji)  \(name.replacingOccurrences(of: "_", with: " "))"
        case .typo(let fix, _): "→ " + fix.trimmingCharacters(in: .whitespaces)
        }
    }
}

/// `:rocket`-style shortcodes from Unicode's own emoji names — no table to
/// maintain (unit-tested).
enum EmojiShortcodes {
    /// (shortcode, emoji), shortest names first so ":fire" finds 🔥 before
    /// "fire_engine".
    static let all: [(name: String, emoji: String)] = {
        let ranges: [ClosedRange<UInt32>] = [0x1F300...0x1F5FF, 0x1F600...0x1F64F, 0x1F680...0x1F6FF, 0x1F900...0x1F9FF,
                                             0x1FA70...0x1FAFF, 0x2600...0x27BF]
        var out: [(String, String)] = []
        for v in ranges.joined() {
            guard let scalar = Unicode.Scalar(v), scalar.properties.isEmojiPresentation, let name = scalar.properties.name
            else { continue }
            out.append((name.lowercased().replacingOccurrences(of: " ", with: "_"), String(scalar)))
        }
        return out.sorted { $0.0.count < $1.0.count }
    }()

    /// The emoji for a `:code` right before the cursor (at least two letters):
    /// names starting with it first, then names with a word starting with it.
    static func match(beforeCursor text: String) -> QuickFix? {
        guard let colon = text.lastIndex(of: ":") else { return nil }
        let code = text[text.index(after: colon)...].lowercased()
        guard code.count >= 2, code.allSatisfy({ $0.isLetter || $0 == "_" }), code.unicodeScalars.allSatisfy(\.isASCII),
              colon == text.startIndex || text[text.index(before: colon)].isWhitespace
        else { return nil }
        let hit = all.first { $0.name.hasPrefix(code) } ?? all.first { $0.name.contains("_" + code) }
        guard let hit else { return nil }
        return .emoji(hit.emoji, name: hit.name, replacing: code.count + 1)
    }
}

/// One-key spelling fix for the word just finished (followed by a space),
/// in the text's own language — macOS's spell checker, on device.
@MainActor
enum TypoFixer {
    static func fix(beforeCursor text: String) -> QuickFix? {
        guard text.last == " " else { return nil }
        let body = text.dropLast()
        let word = String(body.split(whereSeparator: \.isWhitespace).last ?? "")
        guard word.count >= 3, word.allSatisfy(\.isLetter) else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.ukrainian, .english, .russian, .polish, .german]
        recognizer.processString(String(text.suffix(200)))
        let language = recognizer.dominantLanguage?.rawValue ?? "en"
        let checker = NSSpellChecker.shared
        let range = NSRange(location: 0, length: (word as NSString).length)
        let miss = checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false,
                                         inSpellDocumentWithTag: 0, wordCount: nil)
        guard miss.location != NSNotFound,
              let fix = checker.correction(forWordRange: range, in: word, language: language, inSpellDocumentWithTag: 0),
              fix != word
        else { return nil }
        return .typo(fix + " ", replacing: word.count + 1)
    }
}
