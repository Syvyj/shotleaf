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

        SettingsLink { Text("Settings…") }

        Divider()

        Text("Provider: \(coordinator.currentProviderName)")
        if !coordinator.hotkeyRegistered {
            Text("⚠︎ \(coordinator.hotkey.title) is taken by another app")
        }

        Divider()

        Button("Quit APILA") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
