import Foundation

/// The app's name and where its files live — one place, so a rename is one edit.
public enum AppInfo {
    public static let name = "Shotleaf"
    public static let bundleID = "dev.syvyj.shotleaf"

    /// ~/Library/Application Support/Shotleaf
    public static var supportFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name, isDirectory: true)
    }

    /// The app was called APILA (bundle app.apila.APILA) until October 2026.
    public static let oldName = "APILA", oldBundleID = "app.apila.APILA"

    /// Once, on the first launch as Shotleaf: brings over APILA's settings and
    /// files (history, snippets, recent shots, writing style). Asks for the
    /// setup guide again — macOS sees a new app, so its permissions are gone.
    public static func migrateFromAPILA(defaults: UserDefaults = .standard, fileManager: FileManager = .default,
                                        support: URL? = nil, oldDomain: String = oldBundleID) {
        let doneKey = "migratedFromAPILA"
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        let base = support ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = base.appendingPathComponent(oldName, isDirectory: true)
        let new = base.appendingPathComponent(name, isDirectory: true)
        if fileManager.fileExists(atPath: old.path), !fileManager.fileExists(atPath: new.path) {
            try? fileManager.moveItem(at: old, to: new)
        }

        guard let saved = defaults.persistentDomain(forName: oldDomain), !saved.isEmpty else { return }
        // The Keychain key must be saved again by Shotleaf itself (else macOS asks every time).
        let skip: Set<String> = ["shotsKeyOwned", "onboardingCompleted", doneKey]
        for (key, value) in saved where !skip.contains(key) && defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        if let template = defaults.string(forKey: "fileNameTemplate"), template.hasPrefix(oldName + " ") {
            defaults.set(name + template.dropFirst(oldName.count), forKey: "fileNameTemplate")
        }
    }
}
