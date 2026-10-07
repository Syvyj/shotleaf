import Core
import AppKit
import ApplicationServices
import CoreGraphics
import Carbon.HIToolbox

/// Reads the user's current text selection. Injectable seam so the aggregator
/// can be unit-tested without the system.
public protocol SelectedTextReading: Sendable {
    func selectedText(clipboardFallback: Bool) async -> String?
}

/// Real reader: Accessibility first (clean, doesn't touch the clipboard); if the
/// focused app doesn't expose AX selection, fall back to simulating ⌘C and
/// reading the pasteboard — restoring the user's original clipboard afterwards.
public struct AXSelectedTextReader: SelectedTextReading {
    public init() {}

    public func selectedText(clipboardFallback: Bool) async -> String? {
        if let viaAX = Self.readViaAX() { return viaAX }
        guard clipboardFallback else { return nil }
        return await Self.readViaCopy()
    }

    // MARK: Accessibility

    private static func readViaAX() -> String? {
        // Literals avoid referencing the non-Sendable AX global vars under Swift 6.
        let kFocused = "AXFocusedUIElement" as CFString
        let kSelected = "AXSelectedText" as CFString

        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kFocused, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }

        let element = focused as! AXUIElement
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kSelected, &value) == .success,
              let text = value as? String, !text.isEmpty
        else { return nil }
        return text
    }

    // MARK: ⌘C fallback (saves & restores the clipboard)

    @MainActor
    private static func readViaCopy() async -> String? {
        let pasteboard = NSPasteboard.general
        let original = PasteboardSnapshot(pasteboard)
        let beforeCount = pasteboard.changeCount

        // The activation hotkey (e.g. ⌘⇧Space) may still be physically held; a
        // lingering Shift/Option would turn our synthetic ⌘C into ⌘⇧C/⌥⌘C and no
        // copy happens. Give the user a moment to release before synthesizing.
        try? await Task.sleep(nanoseconds: 150_000_000)

        postCommandC()

        var changed = false
        for _ in 0..<30 { // poll up to ~300ms
            try? await Task.sleep(nanoseconds: 10_000_000)
            if pasteboard.changeCount != beforeCount { changed = true; break }
        }
        // Nothing was copied (no selection) → the clipboard is untouched; leave it.
        guard changed else { return nil }
        let grabbed = pasteboard.string(forType: .string)
        original.restore(to: pasteboard)
        return grabbed
    }

    private static func postCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_C)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
