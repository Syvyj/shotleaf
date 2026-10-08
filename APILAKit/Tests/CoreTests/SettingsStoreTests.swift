import Testing
import Foundation
@testable import SettingsKit

@Suite("SettingsStore")
struct SettingsStoreTests {
    @Test("Translate languages default to English ⇄ Ukrainian and persist")
    func translateDefaults() throws {
        let suite = "apila.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        #expect(store.translateTarget == "English")
        #expect(store.translateFallback == "Ukrainian")
        store.translateTarget = "German"
        #expect(SettingsStore(defaults: defaults).translateTarget == "German")
    }
}
