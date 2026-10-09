import Foundation
import Security

/// Persists user settings. Non-secret prefs → UserDefaults; API keys → Keychain
/// (one item per provider kind, so switching providers keeps each key).
/// Values are plain strings: SettingsKit doesn't know InferenceKit's types.
public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let keychainService: String

    public init(defaults: UserDefaults = .standard, keychainService: String = "app.apila.APILA") {
        self.defaults = defaults
        self.keychainService = keychainService
    }

    // MARK: Provider

    /// `ProviderKind.rawValue` of the chosen provider.
    public var providerKind: String? {
        get { defaults.string(forKey: "providerKind") }
        set { defaults.set(newValue, forKey: "providerKind") }
    }

    /// Base URL override; nil = the kind's default.
    public var baseURL: String? {
        get { defaults.string(forKey: "baseURL") }
        set { defaults.set(newValue, forKey: "baseURL") }
    }

    public var model: String? {
        get { defaults.string(forKey: "model") }
        set { defaults.set(newValue, forKey: "model") }
    }

    /// Override of the provider kind's vision capability; nil = kind default.
    public var supportsVision: Bool? {
        get { defaults.object(forKey: "supportsVision") as? Bool }
        set { defaults.set(newValue, forKey: "supportsVision") }
    }

    // MARK: Behaviour

    /// Id of the chosen global shortcut preset.
    public var hotkey: String? {
        get { defaults.string(forKey: "hotkey") }
        set { defaults.set(newValue, forKey: "hotkey") }
    }

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

    /// Translate turns text into this language…
    public var translateTarget: String {
        get { defaults.string(forKey: "translateTarget") ?? "English" }
        set { defaults.set(newValue, forKey: "translateTarget") }
    }

    /// …or into this one when it is already in the target language.
    public var translateFallback: String {
        get { defaults.string(forKey: "translateFallback") ?? "Ukrainian" }
        set { defaults.set(newValue, forKey: "translateFallback") }
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

    /// The first-run setup guide was finished (or dismissed).
    public var onboardingCompleted: Bool {
        get { defaults.bool(forKey: "onboardingCompleted") }
        set { defaults.set(newValue, forKey: "onboardingCompleted") }
    }

    // MARK: Keychain

    public func apiKey(for kind: String) -> String? {
        var query = keychainQuery(kind)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Empty or nil removes the key.
    @discardableResult
    public func setAPIKey(_ key: String?, for kind: String) -> Bool {
        let query = keychainQuery(kind)
        SecItemDelete(query as CFDictionary)
        guard let key, !key.isEmpty else { return true }
        var item = query
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private func keychainQuery(_ kind: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "apiKey.\(kind)",
        ]
    }
}
