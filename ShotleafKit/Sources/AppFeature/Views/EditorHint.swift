import SwiftUI
import AppKit

/// The editor's key hint: shown the first three times it opens, or until closed.
enum EditorHint {
    static let countKey = "editorHintShown", dismissedKey = "editorHintDismissed", times = 3

    /// Whether to show it this time (and counts the showing).
    static func take(_ defaults: UserDefaults = .standard) -> Bool {
        let shown = defaults.integer(forKey: countKey)
        guard !defaults.bool(forKey: dismissedKey), shown < times else { return false }
        defaults.set(shown + 1, forKey: countKey)
        return true
    }

    static func dismiss(_ defaults: UserDefaults = .standard) { defaults.set(true, forKey: dismissedKey) }

    static var text: String {
        let key = { (tool: AnnotationTool) in tool.keyLabel.isEmpty ? "–" : tool.keyLabel }
        return String(localized: "Hover a tool for its name. \(key(.arrow)) arrow · \(key(.blur)) blur · \(key(.crop)) crop · ⌘C copy and close")
    }
}
