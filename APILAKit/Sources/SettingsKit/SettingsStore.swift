import Foundation

/// Persists user settings in UserDefaults.
public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Behaviour

    /// Shortcut id for an action ("capture", "screenshot-text"…); nil = the
    /// action's default, "off" = disabled.
    public func hotkeyID(for action: String) -> String? {
        defaults.string(forKey: Self.hotkeyKey(action))
    }

    public func setHotkeyID(_ id: String, for action: String) {
        defaults.set(id, forKey: Self.hotkeyKey(action))
    }

    private static func hotkeyKey(_ action: String) -> String {
        action == "screenshot-text" ? "screenshotHotkey" : "hotkey.\(action)" // first one predates the scheme
    }

    /// Show APILA in the Dock (otherwise it lives in the menu bar only).
    public var showInDock: Bool {
        get { defaults.object(forKey: "showInDock") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showInDock") }
    }

    /// Inline completion as you type (needs the built-in model).
    public var completionEnabled: Bool {
        get { defaults.object(forKey: "completionEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "completionEnabled") }
    }

    /// Inline completion may read the text on screen (OCR) for context.
    public var completionUsesScreen: Bool {
        get { defaults.object(forKey: "completionUsesScreen") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "completionUsesScreen") }
    }

    /// Inline completion may use what was just copied.
    public var completionUsesClipboard: Bool {
        get { defaults.object(forKey: "completionUsesClipboard") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "completionUsesClipboard") }
    }

    /// Inline completion: 0 cautious … 1 bold.
    public var completionBoldness: Double {
        get { defaults.object(forKey: "completionBoldness") as? Double ?? 0.5 }
        set { defaults.set(newValue, forKey: "completionBoldness") }
    }

    /// Emoji for :shortcodes and one-key spelling fixes.
    public var completionQuickFixes: Bool {
        get { defaults.object(forKey: "completionQuickFixes") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "completionQuickFixes") }
    }

    /// Learn the user's style from their own texts (kept on this Mac).
    public var completionLearnsStyle: Bool {
        get { defaults.object(forKey: "completionLearnsStyle") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "completionLearnsStyle") }
    }

    /// The first-run setup guide was finished (or dismissed).
    public var onboardingCompleted: Bool {
        get { defaults.bool(forKey: "onboardingCompleted") }
        set { defaults.set(newValue, forKey: "onboardingCompleted") }
    }
}
