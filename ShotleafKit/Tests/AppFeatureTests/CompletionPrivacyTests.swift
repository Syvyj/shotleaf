import Testing
import Foundation
import Carbon.HIToolbox
@testable import AppFeature

@Suite("Inline completion privacy")
struct CompletionPrivacyTests {
    @Test("Secure input: nothing is read while it's on")
    func secureInput() {
        #expect(!InlineCompletion.inputIsSecure)
        EnableSecureEventInput()
        defer { DisableSecureEventInput() }
        #expect(InlineCompletion.inputIsSecure)
    }

    @Test("Excluded apps: terminals always, plus the clipboard's list (default or the user's)")
    func excludedApps() {
        let defaults = UserDefaults(suiteName: "CompletionPrivacyTests")!
        defaults.removePersistentDomain(forName: "CompletionPrivacyTests")
        #expect(InlineCompletion.excludedApps(defaults).isSuperset(of: ["com.apple.Terminal", "com.1password.1password", "com.apple.Passwords"]))
        defaults.set("com.example.notes\ncom.apple.Terminal", forKey: ClipboardHistory.excludedKey)
        let mine = InlineCompletion.excludedApps(defaults)
        #expect(mine.contains("com.example.notes") && mine.contains("com.googlecode.iterm2") && !mine.contains("com.1password.1password"))
    }
}
