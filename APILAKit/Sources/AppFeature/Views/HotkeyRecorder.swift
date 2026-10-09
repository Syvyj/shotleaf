import SwiftUI
import AppKit
import Carbon.HIToolbox

/// "Record shortcut…" button: captures the next key press in the Settings
/// window via a local key monitor. Esc cancels.
struct HotkeyRecorder: View {
    let onStart: () -> Void
    let onRecord: (HotkeyShortcut) -> Void
    let onCancel: () -> Void

    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        HStack {
            Button(monitor == nil ? String(localized: "Record shortcut…") : String(localized: "Press keys… (esc cancels)")) {
                monitor == nil ? start() : finish(nil)
            }
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.orange)
            }
        }
        .onDisappear { if monitor != nil { finish(nil) } }
    }

    private func start() {
        hint = nil
        onStart()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // NSEvent isn't Sendable: copy out plain values first.
            let (keyCode, flags, characters) = (event.keyCode, event.modifierFlags, event.charactersIgnoringModifiers)
            MainActor.assumeIsolated {
                if keyCode == UInt16(kVK_Escape) {
                    finish(nil)
                } else if let shortcut = HotkeyShortcut.recorded(keyCode: keyCode, flags: flags, characters: characters) {
                    finish(shortcut)
                } else {
                    hint = String(localized: "Add ⌘, ⌥ or ⌃ (or use an F-key).")
                }
            }
            return nil // swallow: the key press belongs to the recorder
        }
    }

    private func finish(_ shortcut: HotkeyShortcut?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let shortcut { onRecord(shortcut) } else { onCancel() }
    }
}
