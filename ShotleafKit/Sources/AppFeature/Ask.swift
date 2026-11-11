import AppKit

/// A modal note or question in front of everything.
@MainActor
enum Ask {
    /// True when the first button was pressed (with no buttons it's the system's OK).
    @discardableResult
    static func show(_ title: String, _ text: String, buttons: [String] = [], warning: Bool = false) -> Bool {
        let alert = NSAlert()
        if warning { alert.alertStyle = .warning }
        alert.messageText = title
        alert.informativeText = text
        for button in buttons { alert.addButton(withTitle: button) }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
