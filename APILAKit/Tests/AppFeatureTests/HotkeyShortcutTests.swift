import Testing
import AppKit
import Carbon.HIToolbox
@testable import AppFeature

@Suite("HotkeyShortcut")
struct HotkeyShortcutTests {
    @Test("Recorded shortcut gets Carbon modifiers and Apple-ordered title")
    func recorded() throws {
        let s = try #require(HotkeyShortcut.recorded(keyCode: UInt16(kVK_ANSI_K), flags: [.command, .control], characters: "k"))
        #expect(s.title == "⌃⌘K")
        #expect(s.modifiers == UInt32(cmdKey | controlKey))
        #expect(s.keyCode == UInt32(kVK_ANSI_K))
    }

    @Test("Bare keys and shift-only are rejected; F-keys are allowed alone")
    func rejectsTypingKeys() {
        #expect(HotkeyShortcut.recorded(keyCode: UInt16(kVK_ANSI_K), flags: [], characters: "k") == nil)
        #expect(HotkeyShortcut.recorded(keyCode: UInt16(kVK_ANSI_K), flags: [.shift], characters: "K") == nil)
        #expect(HotkeyShortcut.recorded(keyCode: UInt16(kVK_F5), flags: [], characters: nil)?.title == "F5")
    }

    @Test("Custom shortcut survives a round-trip through its id (settings)")
    func roundTrip() throws {
        let s = try #require(HotkeyShortcut.recorded(keyCode: UInt16(kVK_Space), flags: [.option, .shift], characters: " "))
        #expect(s.title == "⌥⇧Space")
        #expect(HotkeyShortcut.with(id: s.id) == s)
    }

    @Test("Unknown or missing id falls back to the default")
    func fallback() {
        #expect(HotkeyShortcut.with(id: nil) == .default)
        #expect(HotkeyShortcut.with(id: "custom:garbage") == .default)
        #expect(HotkeyShortcut.with(id: "ctrl-space").title == "⌃Space")
    }
}

@Suite("Several global hotkeys")
@MainActor
struct MultiHotkeyTests {
    // Exotic combos so the test never collides with real shortcuts on the Mac.
    private let a = HotkeyShortcut.recorded(keyCode: UInt16(kVK_F11), flags: [.command, .option, .control, .shift], characters: nil)!
    private let b = HotkeyShortcut.recorded(keyCode: UInt16(kVK_F12), flags: [.command, .option, .control, .shift], characters: nil)!

    @Test("Two ids can't share a combo; removing frees it; stop/start keeps choices")
    func clashes() {
        let service = GlobalHotkeyService()
        defer { service.stop() }
        #expect(service.setShortcut(a, for: "panel"))
        #expect(!service.setShortcut(a, for: "shot"))
        #expect(service.shortcut(for: "shot") == nil)
        #expect(service.setShortcut(b, for: "shot"))

        #expect(service.setShortcut(nil, for: "panel"))
        #expect(service.setShortcut(a, for: "shot"))
        #expect(service.shortcut(for: "shot") == a)

        service.stop()
        #expect(service.start())
        #expect(service.shortcut(for: "shot") == a)
    }

    @Test("Action hotkey setting: unset → default, \"off\" → none, id → that shortcut")
    func savedSetting() {
        #expect(AppCoordinator.savedHotkey(nil, default: .screenshotDefault) == .screenshotDefault)
        #expect(AppCoordinator.savedHotkey("off", default: .screenshotDefault) == nil)
        #expect(AppCoordinator.savedHotkey(a.id, default: .screenshotDefault) == a)
        #expect(HotkeyShortcut.with(id: HotkeyShortcut.captureDefault.id) == .captureDefault)
    }
}
