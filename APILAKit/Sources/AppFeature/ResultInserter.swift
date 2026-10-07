import Core
import ContextKit
import AppKit
import CoreGraphics
import Carbon.HIToolbox

/// Puts an AI result back where the user was working. Simple path (no complex AX):
/// write to clipboard, re-activate the source app, and synthesize ⌘V. "Insert
/// below" first collapses the selection (→) and adds a newline.
@MainActor
public struct ResultInserter {
    private let clipboard: any ClipboardService

    public init(clipboard: any ClipboardService) {
        self.clipboard = clipboard
    }

    public func copy(_ text: String) async {
        try? await clipboard.writeText(text)
    }

    public func replaceSelection(_ text: String, in app: NSRunningApplication?) async {
        await pasteBorrowingClipboard(text, app: app, insertBelow: false)
    }

    public func insertBelow(_ text: String, in app: NSRunningApplication?) async {
        await pasteBorrowingClipboard(text, app: app, insertBelow: true)
    }

    /// The clipboard is only a transport for ⌘V: afterwards the user's own
    /// clipboard (any types) comes back, unless they copied something meanwhile.
    private func pasteBorrowingClipboard(_ text: String, app: NSRunningApplication?, insertBelow: Bool) async {
        let pasteboard = NSPasteboard.general
        let original = PasteboardSnapshot(pasteboard)
        try? await clipboard.writeText(text)
        let ours = pasteboard.changeCount
        await activateAndPaste(app: app, insertBelow: insertBelow)
        // ponytail: fixed delay for the target app to read the pasteboard; slow apps
        // (Electron under load) may need more — make it a setting if users report it.
        try? await Task.sleep(nanoseconds: 500_000_000)
        if pasteboard.changeCount == ours { original.restore(to: pasteboard) }
    }

    private func activateAndPaste(app: NSRunningApplication?, insertBelow: Bool) async {
        app?.activate()
        try? await Task.sleep(nanoseconds: 150_000_000) // let the app come forward
        if insertBelow {
            postKey(CGKeyCode(kVK_RightArrow))
            postKey(CGKeyCode(kVK_Return))
        }
        postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }

    private func postKey(_ key: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
