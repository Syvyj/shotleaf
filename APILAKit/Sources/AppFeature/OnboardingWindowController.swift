import AppKit
import SwiftUI

/// A plain titled window for the setup guide. APILA is a menu-bar (accessory)
/// app, so it activates itself to bring the window forward.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private let content: () -> AnyView

    init(content: @escaping () -> AnyView) {
        self.content = content
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Welcome to Shotleaf")
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: content())
        hosting.sizingOptions = [.preferredContentSize]
        window.contentView = hosting
        window.center()
        return window
    }
}
