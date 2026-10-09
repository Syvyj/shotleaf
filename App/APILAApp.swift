import SwiftUI
import AppFeature

/// Thin entry point. All logic lives in the AppFeature package; this target only
/// provides the `@main`, the scenes, and the signable bundle for TCC permissions.
/// Starts as a menu-bar agent (LSUIElement = YES); "Show in Dock" in Settings
/// switches to a regular Dock app at runtime. The main UI is the floating panel.
@main
struct APILAApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(coordinator: delegate.coordinator)
        } label: {
            Image(nsImage: BrandMark.menuBarIcon)
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
        if CommandLine.arguments.contains("--completion-eval") { // developer run, see CompletionEval
            Task { await CompletionEval.run(); exit(0) }
            return
        }
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

    /// Clicking the Dock icon (when shown) opens Settings — there's no main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { coordinator.openSettingsWindow() }
        return true
    }
}
