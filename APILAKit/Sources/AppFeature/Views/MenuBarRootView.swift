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
        Button(coordinator.screenshotHotkey.map { "Text from Screenshot… (\($0.title))" } ?? "Text from Screenshot…") {
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

    private static func preview(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return flat.count > 50 ? String(flat.prefix(50)) + "…" : flat
    }
}
