import Foundation

/// The text side of inline completion (unit-tested): what to send the model,
/// how to tidy its answer, word-by-word accept, and keeping a suggestion while
/// the user types the same letters.
enum CompletionText {
    /// How much text before the cursor the model sees.
    static let contextLimit = 600
    /// Longest suggestion shown, in words (at the middle of the boldness scale).
    static let maxWords = 6

    /// The "cautious ↔ bold" setting (0…1): how sure the model must be of
    /// each token, and how many words a suggestion may run.
    struct Boldness: Equatable {
        let value: Double
        init(_ value: Double) { self.value = min(max(value, 0), 1) }
        /// 0.12 when cautious … 0.01 when bold.
        var minTokenProbability: Float { Float(0.12 - 0.11 * value) }
        /// 3 words when cautious … 9 when bold.
        var maxWords: Int { 3 + Int((6 * value).rounded()) }
    }

    /// The prompt: the end of the text before the cursor, without trailing
    /// spaces — the model's next token then brings its own leading space.
    static func prompt(beforeCursor text: String) -> String {
        var tail = String(text.suffix(contextLimit))
        while tail.last?.isWhitespace == true { tail.removeLast() }
        return tail
    }

    /// What else the model may know besides the text before the cursor.
    struct Context: Equatable {
        var app: String?
        var window: String?
        /// Text read off the window (OCR) — the conversation, the page.
        var screen: String?
        /// Something the user copied a moment ago.
        var clipboard: String?
        /// The rest of the line after the cursor (suggesting mid-text).
        var afterCursor: String?
        /// A couple of the user's own earlier texts in this app (their style).
        var examples: [String] = []
    }

    static let screenLimit = 400
    static let clipboardLimit = 400

    /// Base-model prompt with context: short labelled notes first, then a
    /// rule, then the user's text — so the next token continues *their* text.
    static func prompt(beforeCursor text: String, context: Context) -> String {
        let body = prompt(beforeCursor: text)
        var notes: [String] = []
        let examples = context.examples.map { String($0.suffix(300)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !examples.isEmpty {
            notes.append("Earlier by the same writer:\n" + examples.map { "- " + $0.replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\n"))
        }
        let where_ = [context.app, context.window].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !where_.isEmpty { notes.append("App: " + where_.joined(separator: " — ")) }
        if let screen = context.screen.map({ screenLines($0, without: body) }), !screen.isEmpty {
            notes.append("On screen:\n" + String(screen.suffix(screenLimit)))
        }
        if let clip = context.clipboard?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty {
            notes.append("Just copied:\n" + String(clip.prefix(clipboardLimit)))
        }
        if let after = context.afterCursor?.trimmingCharacters(in: .whitespaces), !after.isEmpty {
            notes.append("Text right after the cursor:\n" + String(after.prefix(200)))
        }
        return notes.isEmpty ? body : notes.joined(separator: "\n\n") + "\n\n---\n\n" + body
    }

    /// Screen text minus the lines the user is typing anyway (OCR sees the
    /// field too).
    static func screenLines(_ screen: String, without typed: String) -> String {
        screen.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !($0.count >= 8 && typed.contains($0)) }
            .joined(separator: "\n")
    }

    /// Worth asking the model: some real text, and the cursor isn't mid-word
    /// right after a single letter.
    static func shouldComplete(beforeCursor text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 3 && text.last != "\n"
    }

    /// A base model's raw continuation → the text to show after the cursor:
    /// one line, one sentence at most, no loops, no doubled space. When the
    /// model was cut off (`finished` false — unsure, or still writing) a
    /// half-written last word is dropped.
    static func suggestion(
        fromContinuation raw: String, finished: Bool = true, beforeCursor text: String,
        afterCursor: String = "", maxWords: Int = CompletionText.maxWords
    ) -> String? {
        var line = String(raw.prefix { $0 != "\n" && $0 != "\r" })
        if let end = line.firstIndex(where: { ".!?…".contains($0) }) {
            line = String(line[...end]) // the sentence ends here; a full stop counts as finished
        } else if !finished {
            line = withoutPartialWord(line)
        }
        guard var shown = clean(withoutRepeats(line, after: text), beforeCursor: text, maxWords: maxWords) else { return nil }
        // Mid-text: stop before the words that already follow the cursor.
        let next = afterCursor.trimmingCharacters(in: .whitespaces)
        if !next.isEmpty {
            guard shown.contains(where: \.isLetter) else { return nil } // a lone "!" mid-text isn't worth a badge
            let firstNext = next.split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
            let words = shown.split(whereSeparator: \.isWhitespace)
            if let i = words.firstIndex(where: { $0.lowercased() == firstNext }) {
                guard i > 0 else { return nil }
                shown = (shown.first == " " ? " " : "") + words[..<i].joined(separator: " ")
            }
        }
        return shown
    }

    /// Drops a word the model hadn't finished. A suggestion that only
    /// finishes the user's current word (no space in it) stays as it is.
    static func withoutPartialWord(_ line: String) -> String {
        guard let lastSpace = line.lastIndex(where: \.isWhitespace) else { return line }
        let hasWordBefore = line[..<lastSpace].contains { !$0.isWhitespace }
        return hasWordBefore ? String(line[..<lastSpace]) : "" // " повн" alone: nothing sure yet
    }

    /// Cuts the suggestion where it starts going round in circles: a word
    /// pair it already said, or the pair the user just typed.
    static func withoutRepeats(_ suggestion: String, after text: String) -> String {
        func words(_ s: String) -> [String] { s.lowercased().split(whereSeparator: \.isWhitespace).map(String.init) }
        let mine = words(suggestion)
        var seen = Set<String>()
        let typed = words(String(text.suffix(200)))
        if typed.count >= 2 { seen.insert(typed.suffix(2).joined(separator: " ")) }
        for i in mine.indices.dropLast() {
            let pair = mine[i] + " " + mine[i + 1]
            if seen.contains(pair) {
                // Keep the words before the repeat (by position in the original text).
                var count = 0, end = suggestion.startIndex, inWord = false
                for j in suggestion.indices {
                    let space = suggestion[j].isWhitespace
                    if !space && !inWord { if count == i { break }; count += 1 }
                    inWord = !space
                    end = suggestion.index(after: j)
                }
                var kept = String(suggestion[..<end])
                while kept.last?.isWhitespace == true { kept.removeLast() }
                return kept
            }
            seen.insert(pair)
        }
        return suggestion
    }

    /// Tidy text to show: one line, at most `maxWords` words, no doubled
    /// space when the user already typed one.
    static func clean(_ raw: String, beforeCursor text: String, maxWords: Int = CompletionText.maxWords) -> String? {
        var line = String(raw.prefix { $0 != "\n" && $0 != "\r" })
        if text.last?.isWhitespace == true {
            while line.first == " " { line.removeFirst() }
        }
        var words = 0
        var end = line.startIndex
        var inWord = false
        for i in line.indices {
            let space = line[i].isWhitespace
            if !space && !inWord { words += 1 }
            if words > maxWords { break }
            inWord = !space
            end = line.index(after: i)
        }
        line = String(line[..<end])
        while line.last?.isWhitespace == true { line.removeLast() }
        return line.trimmingCharacters(in: .whitespaces).isEmpty ? nil : line
    }

    /// Tab: the next word with the spaces before it and punctuation stuck to it.
    static func nextWord(of suggestion: String) -> (word: String, rest: String) {
        var i = suggestion.startIndex
        while i < suggestion.endIndex, suggestion[i].isWhitespace { i = suggestion.index(after: i) }
        while i < suggestion.endIndex, !suggestion[i].isWhitespace { i = suggestion.index(after: i) }
        return (String(suggestion[..<i]), String(suggestion[i...]))
    }

    /// The user typed `typed`: if the suggestion starts with it, the rest stays
    /// on screen ("adapts within a letter"); otherwise the suggestion is gone.
    static func advance(_ suggestion: String, typed: String) -> String? {
        guard !typed.isEmpty, suggestion.hasPrefix(typed) else { return nil }
        let rest = String(suggestion.dropFirst(typed.count))
        return rest.trimmingCharacters(in: .whitespaces).isEmpty ? nil : rest
    }
}
