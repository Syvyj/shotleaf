import Testing
import Foundation
@testable import SettingsKit

@Suite("SettingsStore")
struct SettingsStoreTests {
    @Test("A shortcut choice persists")
    func persists() throws {
        let suite = "shotleaf.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        store.setHotkeyID("off", for: "scrolling")
        let reread = SettingsStore(defaults: defaults)
        #expect(reread.hotkeyID(for: "scrolling") == "off")
    }
}
