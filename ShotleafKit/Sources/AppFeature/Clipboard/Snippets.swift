import Core
import AppKit

/// A saved text to paste again, with optional variables and an abbreviation.
struct Snippet: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var text: String
    /// Typed anywhere, e.g. ";addr", it turns into the text.
    var abbreviation = ""
    var folder: UUID?
}

struct SnippetFolder: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// Index into `SnippetFolder.colors`.
    var color = 0

    static let colors: [NSColor] = [
        NSColor(srgbRed: 0.39, green: 0.60, blue: 0.13, alpha: 1), NSColor(srgbRed: 0.22, green: 0.54, blue: 0.87, alpha: 1),
        NSColor(srgbRed: 0.85, green: 0.35, blue: 0.19, alpha: 1), NSColor(srgbRed: 0.50, green: 0.47, blue: 0.87, alpha: 1),
        NSColor(srgbRed: 0.73, green: 0.46, blue: 0.09, alpha: 1), NSColor(srgbRed: 0.83, green: 0.33, blue: 0.49, alpha: 1),
    ]
}

/// The user's snippets and folders (Application Support/Shotleaf/snippets.json).
@MainActor
@Observable
final class SnippetStore {
    var snippets: [Snippet] = [] { didSet { save() } }
    var folders: [SnippetFolder] = [] { didSet { save() } }
    let file: URL
    private var loading = false

    init(file: URL = SnippetStore.defaultFile) {
        self.file = file
        loading = true
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            snippets = saved.snippets
            folders = saved.folders
        }
        loading = false
    }

    static var defaultFile: URL {
        AppInfo.supportFolder.appendingPathComponent("snippets.json")
    }

    private struct Saved: Codable {
        var snippets: [Snippet]
        var folders: [SnippetFolder]
    }

    private func save() {
        guard !loading else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(Saved(snippets: snippets, folders: folders)).write(to: file, options: .atomic)
    }

    /// Every word of `query` in the title, text or abbreviation.
    func search(_ query: String) -> [Snippet] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        return snippets.filter { s in
            let haystack = "\(s.title)\n\(s.text)\n\(s.abbreviation)".lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    func folder(_ id: UUID?) -> SnippetFolder? { folders.first { $0.id == id } }
}

/// Fills a snippet's variables: {date}, {time}, {clipboard}, {cursor} (where
/// the caret ends up) and {?Question} (asked before pasting).
enum SnippetText {
    static let variables = ["{date}", "{time}", "{clipboard}", "{cursor}", "{?…}"]

    /// The questions in order, without repeats ("{?Name}" → "Name").
    static func questions(in text: String) -> [String] {
        var seen: [String] = []
        for match in text.matches(of: /\{\?([^}]+)\}/) where !seen.contains(String(match.1)) { seen.append(String(match.1)) }
        return seen
    }

    /// The text to paste, and how many characters come after {cursor} (0 = none).
    static func expand(_ text: String, answers: [String: String] = [:], clipboard: String = "", now: Date = Date()) -> (text: String, afterCursor: Int) {
        let day = DateFormatter()
        day.locale = .current
        day.dateStyle = .short
        let time = DateFormatter()
        time.locale = .current
        time.timeStyle = .short
        var out = text
            .replacingOccurrences(of: "{date}", with: day.string(from: now))
            .replacingOccurrences(of: "{time}", with: time.string(from: now))
            .replacingOccurrences(of: "{clipboard}", with: clipboard)
        for (question, answer) in answers { out = out.replacingOccurrences(of: "{?\(question)}", with: answer) }
        out = out.replacing(/\{\?[^}]+\}/, with: "") // unanswered
        guard let marker = out.range(of: "{cursor}") else { return (out, 0) }
        let tail = out[marker.upperBound...].replacingOccurrences(of: "{cursor}", with: "") // only the first counts
        return (out[..<marker.lowerBound] + tail, tail.count)
    }
}
