import Core
import AppKit

/// A saved text (and pictures) to paste again, with optional variables and an abbreviation.
struct Snippet: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var text: String
    /// Typed anywhere, e.g. ";addr", it turns into the text.
    var abbreviation = ""
    var folder: UUID?
    /// Pictures pasted along with the text: file names in the store's image folder.
    /// Optional: snippets saved before pictures have no such field.
    var images: [String]?
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
    /// Snippets' pictures, next to snippets.json.
    let imageFolder: URL
    private var loading = false

    init(file: URL = SnippetStore.defaultFile) {
        self.file = file
        imageFolder = file.deletingLastPathComponent().appendingPathComponent("Snippet Images", isDirectory: true)
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
        // Pictures no snippet uses any more go. ponytail: a full sweep per save, fine for hundreds of files.
        let used = Set(snippets.flatMap { $0.images ?? [] })
        for name in (try? FileManager.default.contentsOfDirectory(atPath: imageFolder.path)) ?? [] where !used.contains(name) {
            try? FileManager.default.removeItem(at: imageURL(name))
        }
    }

    // MARK: Sharing a folder

    /// A folder's snippets as files in `dir`: each picture as "<title>.png"
    /// ("<title> 2.png"…), and the texts together in "<folder>.txt". For the
    /// share menu (AirDrop, Mail, Messages) or a copy in Finder.
    func exportFiles(of folderID: UUID, into dir: URL) -> [URL] {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let clean = { (name: String) in name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") }
        var urls: [URL] = [], used: Set<String> = []
        let inFolder = snippets.filter { $0.folder == folderID }
        for snippet in inFolder {
            for source in imageURLs(snippet) {
                let base = clean(snippet.title.isEmpty ? String(localized: "Image") : snippet.title)
                var name = base + ".png", n = 2
                while used.contains(name) { name = "\(base) \(n).png"; n += 1 }
                used.insert(name)
                let target = dir.appendingPathComponent(name)
                try? fm.removeItem(at: target)
                if (try? fm.copyItem(at: source, to: target)) != nil { urls.append(target) }
            }
        }
        let texts = inFolder.filter { !$0.text.isEmpty }.map { "\($0.title)\n\($0.text)" }
        if !texts.isEmpty {
            let file = dir.appendingPathComponent(clean(folder(folderID)?.name ?? String(localized: "Snippets")) + ".txt")
            if (try? texts.joined(separator: "\n\n———\n\n").write(to: file, atomically: true, encoding: .utf8)) != nil { urls.append(file) }
        }
        return urls
    }

    // MARK: Pictures

    func imageURL(_ name: String) -> URL { imageFolder.appendingPathComponent(name) }

    func imageURLs(_ snippet: Snippet) -> [URL] { (snippet.images ?? []).map(imageURL) }

    /// Keeps a picture for a snippet; its file name, to put in `images`.
    func addImage(_ png: Data) -> String? {
        try? FileManager.default.createDirectory(at: imageFolder, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".png"
        do { try png.write(to: imageURL(name)) } catch { return nil }
        return name
    }

    /// A new snippet from what was copied or captured: text and pictures, into `folder`.
    @discardableResult
    func save(title: String, text: String, pngs: [Data], folder: UUID?) -> Snippet {
        let names = pngs.compactMap(addImage)
        let snippet = Snippet(title: title, text: text, folder: self.folder(folder) == nil ? nil : folder, images: names.isEmpty ? nil : names)
        snippets.insert(snippet, at: 0)
        return snippet
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
