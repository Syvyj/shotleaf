import Foundation

/// The text side of inline completion (unit-tested): what to send the model,
/// how to tidy its answer, word-by-word accept, and keeping a suggestion while
/// the user types the same letters.
enum CompletionText {
    /// How much text before the cursor the model sees.
    static let contextLimit = 1500
    /// Longest suggestion shown, in words.
    static let maxWords = 6

    /// The prompt: the end of the text before the cursor, without trailing
    /// spaces — the model's next token then brings its own leading space.
    static func prompt(beforeCursor text: String) -> String {
        var tail = String(text.suffix(contextLimit))
        while tail.last?.isWhitespace == true { tail.removeLast() }
        return tail
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
    static func suggestion(fromContinuation raw: String, finished: Bool = true, beforeCursor text: String) -> String? {
        var line = String(raw.prefix { $0 != "\n" && $0 != "\r" })
        if let end = line.firstIndex(where: { ".!?…".contains($0) }) {
            line = String(line[...end]) // the sentence ends here; a full stop counts as finished
        } else if !finished {
            line = withoutPartialWord(line)
        }
        return clean(withoutRepeats(line, after: text), beforeCursor: text)
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
    static func clean(_ raw: String, beforeCursor text: String) -> String? {
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
