import Core
import Foundation

/// Persists user settings (selected provider, hotkeys, endpoints). Secrets go to
/// the Keychain; non-secret prefs to UserDefaults. Currently an in-memory stub.
public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var selectedProviderID: String? {
        get { defaults.string(forKey: "selectedProviderID") }
        set { defaults.set(newValue, forKey: "selectedProviderID") }
    }
}
