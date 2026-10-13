import AppKit

/// A file Shotleaf meant to keep couldn't be written (disk full, folder gone,
/// no permission). Said out loud: losing a screenshot or a snippet silently is
/// worse than an alert. The same failure isn't repeated within a minute.
@MainActor
enum SaveError {
    private static var lastShown: (message: String, at: Date)?

    static func show(_ error: Error, saving what: String) {
        let message = error.localizedDescription
        if let last = lastShown, last.message == message, Date().timeIntervalSince(last.at) < 60 { return }
        lastShown = (message, Date())
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn’t save \(what)")
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }
}
