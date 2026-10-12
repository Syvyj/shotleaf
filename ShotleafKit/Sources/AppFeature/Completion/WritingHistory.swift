import Core
import Foundation

/// The user's own finished texts, a few per app, so suggestions sound like
/// them ("learns your style"). Kept on this Mac only, in
/// Application Support; never sent anywhere; "Forget" wipes it.
/// A text is remembered when the user leaves the field they wrote it in.
@MainActor
final class WritingHistory {
    var enabled = true
    private let url: URL
    private var passages: [String: [String]] = [:] // bundle id → newest last
    static let perApp = 20
    static let passageLength = 300

    init(url: URL = WritingHistory.defaultURL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([String: [String]].self, from: data) {
            passages = saved
        }
    }

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppInfo.name, isDirectory: true).appendingPathComponent("writing-history.json")
    }

    func remember(_ text: String, app: String) {
        guard enabled else { return }
        let passage = String(text.suffix(Self.passageLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard passage.count >= 40 else { return } // too short to say anything about style
        var list = passages[app, default: []].filter { $0 != passage && !passage.hasPrefix($0) }
        list.append(passage)
        passages[app] = Array(list.suffix(Self.perApp))
        save()
    }

    /// Two recent texts from this app that aren't the one being written.
    func examples(for app: String, current: String) -> [String] {
        guard enabled else { return [] }
        let now = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(passages[app, default: []].reversed().filter { now.isEmpty || (!now.hasPrefix($0) && !$0.hasPrefix(now)) }.prefix(2))
    }

    var isEmpty: Bool { passages.values.allSatisfy(\.isEmpty) }

    func forget() {
        passages = [:]
        try? FileManager.default.removeItem(at: url)
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(passages).write(to: url, options: .atomic)
    }
}
