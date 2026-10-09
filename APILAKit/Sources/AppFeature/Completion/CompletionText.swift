import Foundation

/// The text side of inline completion (unit-tested): what to send the model,
/// how to tidy its answer, word-by-word accept, and keeping a suggestion while
/// the user types the same letters.
enum CompletionText {
    /// How much text before the cursor the model sees.
    static let contextLimit = 1500
    /// Longest suggestion shown, in words.
    static let maxWords = 8

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

    /// The model's raw continuation → what to show: one line, at most
    /// `maxWords` words, no doubled space when the user already typed one.
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
