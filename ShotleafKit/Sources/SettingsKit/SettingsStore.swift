import Foundation
import Core

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

    /// Show Shotleaf in the Dock (otherwise it lives in the menu bar only).
    public var showInDock: Bool {
        get { defaults.object(forKey: "showInDock") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showInDock") }
    }

    /// Ask GitHub once a day whether a newer Shotleaf is out.
    public var checksForUpdates: Bool {
        get { defaults.object(forKey: "checksForUpdates") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "checksForUpdates") }
    }

    // MARK: Screenshots

    /// What a new screenshot does: open the editor, or go straight to the clipboard / a file.
    public enum AfterCapture: String, CaseIterable, Sendable {
        case editor, copy, save, copyAndSave
    }

    public var afterCapture: AfterCapture {
        get { defaults.string(forKey: "afterCapture").flatMap(AfterCapture.init) ?? .editor }
        set { defaults.set(newValue.rawValue, forKey: "afterCapture") }
    }

    /// Where screenshots are saved; nil = the Desktop.
    public var saveFolder: URL? {
        get { defaults.string(forKey: "saveFolder").flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) } }
        set { defaults.set(newValue?.path, forKey: "saveFolder") }
    }

    /// File name without extension; {date} and {time} are filled in.
    public static let defaultFileName = "Shotleaf {date} at {time}"
    public var fileNameTemplate: String {
        get { defaults.string(forKey: "fileNameTemplate") ?? Self.defaultFileName }
        set { defaults.set(newValue, forKey: "fileNameTemplate") }
    }

    /// Save Retina shots at half the pixels (smaller files).
    public var saveAt1x: Bool {
        get { defaults.bool(forKey: "saveAt1x") }
        set { defaults.set(newValue, forKey: "saveAt1x") }
    }

    /// Seconds to wait before the screenshot shortcut starts (0 = none).
    public var captureDelay: Int {
        get { defaults.integer(forKey: "captureDelay") }
        set { defaults.set(newValue, forKey: "captureDelay") }
    }

    /// Put the mouse pointer into screenshots (read by the picker directly).
    public static let showsCursorKey = DefaultsKey.captureShowsCursor
    public var captureShowsCursor: Bool {
        get { defaults.bool(forKey: Self.showsCursorKey) }
        set { defaults.set(newValue, forKey: Self.showsCursorKey) }
    }

    /// Last size limit picked for an image / video (bytes); "Copy Smaller" and the recording window reuse it.
    public var smallImageLimit: Int {
        get { defaults.object(forKey: "smallImageLimit") as? Int ?? 1_000_000 }
        set { defaults.set(newValue, forKey: "smallImageLimit") }
    }

    public var smallVideoLimit: Int {
        get { defaults.object(forKey: "smallVideoLimit") as? Int ?? 8_000_000 }
        set { defaults.set(newValue, forKey: "smallVideoLimit") }
    }

    /// The first-run setup guide was finished (or dismissed).
    public var onboardingCompleted: Bool {
        get { defaults.bool(forKey: "onboardingCompleted") }
        set { defaults.set(newValue, forKey: "onboardingCompleted") }
    }
}
