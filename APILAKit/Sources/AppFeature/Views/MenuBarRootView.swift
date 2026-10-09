import SwiftUI
import AppKit

/// The menu bar menu: Open APILA · Permissions · Current Provider · Quit.
public struct MenuBarRootView: View {
    @Bindable private var coordinator: AppCoordinator

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        Button("Open APILA (\(coordinator.hotkey.title))") { coordinator.openFromMenu() }
        Button(Self.label(String(localized: "Screenshot…"), coordinator.actionHotkeys[.capture])) {
            coordinator.takeScreenshot()
        }
        Button(Self.label(String(localized: "Scrolling Screenshot…"), coordinator.actionHotkeys[.scrolling])) { coordinator.takeScrollingScreenshot() }
        Menu("Screenshot with Delay") {
            Button("In 3 Seconds") { coordinator.takeScreenshot(delay: 3) }
            Button("In 5 Seconds") { coordinator.takeScreenshot(delay: 5) }
            Button("In 10 Seconds") { coordinator.takeScreenshot(delay: 10) }
        }
        Button(Self.label(String(localized: "Text from Screenshot…"), coordinator.actionHotkeys[.screenshotText])) {
            coordinator.screenshotFromMenu(ask: false)
        }
        Button("Ask about Screenshot…") { coordinator.screenshotFromMenu(ask: true) }

        if !coordinator.history.isEmpty {
            Menu("Recent Results") {
                ForEach(coordinator.history) { entry in
                    Button("\(entry.title): \(Self.preview(entry.output))") {
                        coordinator.copyFromHistory(entry)
                    }
                }
                Divider()
                Button("Clear") { coordinator.clearHistory() }
            }
        }

        SettingsLink { Text("Settings…") }
        Button("Setup Guide…") { coordinator.showOnboarding() }

        Divider()

        Text("Provider: \(coordinator.currentProviderName)")
        if !coordinator.hotkeyRegistered {
            Text("⚠︎ \(coordinator.hotkey.title) is taken by another app")
        }

        Divider()

        Button("Quit APILA") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private static func label(_ title: String, _ shortcut: HotkeyShortcut?) -> String {
        shortcut.map { "\(title) (\($0.title))" } ?? title
    }

    private static func preview(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return flat.count > 50 ? String(flat.prefix(50)) + "…" : flat
    }
}
