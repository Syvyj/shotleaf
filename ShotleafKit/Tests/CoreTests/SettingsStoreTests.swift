import Testing
import Foundation
@testable import SettingsKit

@Suite("SettingsStore")
struct SettingsStoreTests {
    @Test("Completion settings default on / middle and persist")
    func completionDefaults() throws {
        let suite = "shotleaf.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        #expect(store.completionEnabled && store.completionBoldness == 0.5)
        store.completionBoldness = 0.8
        store.setHotkeyID("off", for: "scrolling")
        let reread = SettingsStore(defaults: defaults)
        #expect(reread.completionBoldness == 0.8 && reread.hotkeyID(for: "scrolling") == "off")
    }
}
