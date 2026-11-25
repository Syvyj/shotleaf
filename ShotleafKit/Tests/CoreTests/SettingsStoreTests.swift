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

    @Test("Last size limits persist")
    func sizeLimitsPersist() throws {
        let suite = "shotleaf.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fresh = SettingsStore(defaults: defaults)
        #expect(fresh.smallImageLimit == 1_000_000)
        #expect(fresh.smallVideoLimit == 8_000_000)
        fresh.smallImageLimit = 500_000
        fresh.smallVideoLimit = 25_000_000
        let reread = SettingsStore(defaults: defaults)
        #expect(reread.smallImageLimit == 500_000)
        #expect(reread.smallVideoLimit == 25_000_000)
    }
}
