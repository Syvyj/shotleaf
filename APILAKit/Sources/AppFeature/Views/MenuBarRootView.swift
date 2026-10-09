import SwiftUI
import AppKit

/// The menu bar menu: screenshots, text from a screenshot, settings, quit.
public struct MenuBarRootView: View {
    @Bindable private var coordinator: AppCoordinator

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        Button(Self.label(String(localized: "Screenshot…"), coordinator.actionHotkeys[.capture])) {
            coordinator.takeScreenshot()
        }
        Button(Self.label(String(localized: "Scrolling Screenshot…"), coordinator.actionHotkeys[.scrolling])) {
            coordinator.takeScrollingScreenshot()
        }
        Menu("Screenshot with Delay") {
            Button("In 3 Seconds") { coordinator.takeScreenshot(delay: 3) }
            Button("In 5 Seconds") { coordinator.takeScreenshot(delay: 5) }
            Button("In 10 Seconds") { coordinator.takeScreenshot(delay: 10) }
        }
        Button(Self.label(String(localized: "Text from Screenshot…"), coordinator.actionHotkeys[.screenshotText])) {
            coordinator.textFromScreenshot()
        }

        Divider()

        Toggle("Complete my text as I type", isOn: Binding(
            get: { coordinator.completionEnabled }, set: { coordinator.setCompletion($0) }
        ))
        SettingsLink { Text("Settings…") }
        Button("Setup Guide…") { coordinator.showOnboarding() }

        Divider()

        Button("Quit APILA") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private static func label(_ title: String, _ shortcut: HotkeyShortcut?) -> String {
        shortcut.map { "\(title) (\($0.title))" } ?? title
    }
}
