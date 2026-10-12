import Testing
import Foundation
@testable import Core

@Suite("Rename from APILA")
struct AppInfoTests {
    @Test("Moves the files, copies the settings once (not the Keychain flag or the setup guide), renames the file name template")
    func migrate() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("apila-migrate-\(UUID())")
        defer { try? fm.removeItem(at: base) }
        try fm.createDirectory(at: base.appendingPathComponent("APILA/Clipboard"), withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: base.appendingPathComponent("APILA/snippets.json"))

        let suite = "apila-migrate-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // A stand-in for the old app's domain — never the real app.apila.APILA.
        let oldName = "apila-old-\(UUID())"
        let oldDomain = ["afterCapture": "copy", "shotsKeyOwned": true, "onboardingCompleted": true,
                         "fileNameTemplate": "APILA {date} at {time}"] as [String: Any]
        defaults.setPersistentDomain(oldDomain, forName: oldName)
        defer { defaults.removePersistentDomain(forName: oldName) }

        AppInfo.migrateFromAPILA(defaults: defaults, support: base, oldDomain: oldName)
        #expect(fm.fileExists(atPath: base.appendingPathComponent("Shotleaf/snippets.json").path))
        #expect(!fm.fileExists(atPath: base.appendingPathComponent("APILA").path))
        #expect(defaults.string(forKey: "afterCapture") == "copy")
        #expect(defaults.string(forKey: "fileNameTemplate") == "Shotleaf {date} at {time}")
        #expect(defaults.object(forKey: "shotsKeyOwned") == nil && defaults.object(forKey: "onboardingCompleted") == nil)

        defaults.set("save", forKey: "afterCapture")
        AppInfo.migrateFromAPILA(defaults: defaults, support: base, oldDomain: oldName) // only once
        #expect(defaults.string(forKey: "afterCapture") == "save")
    }
}
