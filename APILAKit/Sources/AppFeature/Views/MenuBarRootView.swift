import SwiftUI
import AppKit

/// The menu bar menu: Open APILA · Permissions · Current Provider · Quit.
public struct MenuBarRootView: View {
    @Bindable private var coordinator: AppCoordinator

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        Button("Open APILA (⌘⇧Space)") { coordinator.openFromMenu() }

        SettingsLink { Text("Permissions…") }

        Divider()

        Text("Provider: \(coordinator.currentProviderName)")

        Divider()

        Button("Quit APILA") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
