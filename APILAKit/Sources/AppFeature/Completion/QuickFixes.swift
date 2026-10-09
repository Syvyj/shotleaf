import AppKit
import NaturalLanguage

/// A one-key fix offered at the cursor: replaces text before it.
enum QuickFix: Equatable {
    /// "helo " → "hello ".
    case typo(String, replacing: Int)

    /// Text to type after deleting `replacing` characters.
    var insert: String {
        switch self { case .typo(let fix, _): fix }
    }

    var replacing: Int {
        switch self { case .typo(_, let n): n }
    }

    /// What the badge says.
    var label: String {
        switch self { case .typo(let fix, _): "→ " + fix.trimmingCharacters(in: .whitespaces) }
    }
}

/// Emoji by name, Cotypist-style: `:` or `;` opens a picker of recent emoji,
/// letters after it filter by Unicode's own names (`:roc` → 🚀) — no table
/// to maintain (unit-tested).
enum EmojiShortcodes {
    struct Candidate: Equatable {
        let emoji: String
        let name: String
    }

    /// Every emoji with its name ("rocket", "thumbs_up_sign"), shortest names
    /// first so `:fire` finds 🔥 before "fire_engine".
    static let all: [Candidate] = {
        let ranges: [ClosedRange<UInt32>] = [0x1F300...0x1F5FF, 0x1F600...0x1F64F, 0x1F680...0x1F6FF, 0x1F900...0x1F9FF,
                                             0x1FA70...0x1FAFF, 0x2600...0x27BF]
        var out: [Candidate] = []
        for v in ranges.joined() {
            guard let scalar = Unicode.Scalar(v), scalar.properties.isEmojiPresentation, let name = scalar.properties.name
            else { continue }
            out.append(Candidate(emoji: String(scalar), name: name.lowercased().replacingOccurrences(of: " ", with: "_")))
        }
        return out.sorted { $0.name.count < $1.name.count }
    }()

    /// The picker's query when the text ends with `:` or `;` (after a space
    /// or at the start) plus up to 20 Latin letters: "" right after the
    /// colon, "roc" for `:roc`; nil otherwise (`10:30`, `:-)`, "word;").
    static func query(beforeCursor text: String) -> String? {
        guard let mark = text.lastIndex(where: { $0 == ":" || $0 == ";" }) else { return nil }
        let query = String(text[text.index(after: mark)...])
        guard query.count <= 20, query.allSatisfy({ ($0.isLetter && $0.isASCII) || $0 == "_" }),
              mark == text.startIndex || text[text.index(before: mark)].isWhitespace
        else { return nil }
        return query.lowercased()
    }

    /// Up to `limit` emoji for `query`: the recent ones when it's empty, else
    /// names starting with it, then names with a word starting with it.
    static func candidates(_ query: String, recents: [String], limit: Int = 8) -> [Candidate] {
        if query.isEmpty {
            return recents.prefix(limit).map { emoji in Candidate(emoji: emoji, name: all.first { $0.emoji == emoji }?.name ?? "") }
        }
        let starts = all.filter { $0.name.hasPrefix(query) }
        let inside = all.filter { !$0.name.hasPrefix(query) && $0.name.contains("_" + query) }
        return Array((starts + inside).prefix(limit))
    }
}

/// The emoji the user picked lately, newest first (first time: a common set).
enum EmojiRecents {
    private static let key = "emojiRecents"
    static let starter = ["👍", "😂", "❤️", "🙏", "😊", "🔥", "🎉", "🚀"]

    static var list: [String] { UserDefaults.standard.stringArray(forKey: key) ?? starter }

    static func used(_ emoji: String) {
        UserDefaults.standard.set(Array(([emoji] + list.filter { $0 != emoji }).prefix(16)), forKey: key)
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
