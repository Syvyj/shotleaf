import SwiftUI
import AppFeature

/// Thin entry point. All logic lives in the AppFeature package; this target only
/// provides the `@main`, the scenes, and the signable bundle for TCC permissions.
/// Menu-bar-only agent app (LSUIElement = YES); the UI is the floating panel.
@main
struct APILAApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("APILA", systemImage: "sparkles") {
            MenuBarRootView(coordinator: delegate.coordinator)
        }

        Settings {
            SettingsRootView(coordinator: delegate.coordinator)
        }
    }
}

/// Boots the coordinator at launch (reliable, vs. lazy scene `.task`).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One APILA at a time: two copies fight over the global hotkeys.
        let me = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != me }
        guard others.isEmpty else {
            NSApp.terminate(nil)
            return
        }
        Task { await coordinator.start() }
    }
}
