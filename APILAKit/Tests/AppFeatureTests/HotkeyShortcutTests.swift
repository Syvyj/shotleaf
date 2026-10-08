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
