import Core
import Foundation

/// Text completion was removed in 0.3.0. Its 3.4 GB model and the kept writing samples
/// would otherwise stay on disk for good: both go at launch (cheap once they're gone).
// ponytail: drop this file a few releases after 0.3.0.
enum LeftoverCompletion {
    /// Where the model was downloaded: the Hugging Face cache, unless the environment moved it.
    static func modelFolder(environment: [String: String] = ProcessInfo.processInfo.environment,
                            home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let hub = environment["HF_HUB_CACHE"].map { URL(fileURLWithPath: $0) }
            ?? environment["HF_HOME"].map { URL(fileURLWithPath: $0).appendingPathComponent("hub") }
            ?? home.appendingPathComponent(".cache/huggingface/hub")
        return hub.appendingPathComponent("models--mlx-community--gemma-4-e2b-4bit", isDirectory: true)
    }

    static func remove(environment: [String: String] = ProcessInfo.processInfo.environment,
                       home: URL = FileManager.default.homeDirectoryForCurrentUser, support: URL = AppInfo.supportFolder) {
        try? FileManager.default.removeItem(at: modelFolder(environment: environment, home: home))
        try? FileManager.default.removeItem(at: support.appendingPathComponent("writing-history.json"))
    }

    /// Its settings, from the standard defaults.
    static func forgetSettings(_ defaults: UserDefaults = .standard) {
        for key in ["completionEnabled", "completionUsesScreen", "completionUsesClipboard", "completionBoldness",
                    "completionQuickFixes", "completionLearnsStyle", "emojiRecents"] { defaults.removeObject(forKey: key) }
    }
}
