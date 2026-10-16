import SwiftUI
import AppFeature
import Core

/// Thin entry point. All logic lives in the AppFeature package; this target only
/// provides the `@main`, the scenes, and the signable bundle for TCC permissions.
/// Starts as a menu-bar agent (LSUIElement = YES); "Show in Dock" in Settings
/// switches to a regular Dock app at runtime. The main UI is the floating panel.
@main
struct ShotleafApp: App {
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
    let coordinator: AppCoordinator

    override init() {
        AppInfo.migrateFromAPILA() // before anything reads the settings or the files
        coordinator = AppCoordinator()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--ax-watch") { // developer run, read-only
            let args = CommandLine.arguments
            let out = URL(fileURLWithPath: args.count > i + 1 ? args[i + 1] : NSTemporaryDirectory())
            let seconds = args.count > i + 2 ? Double(args[i + 2]) ?? 180 : 180
            Task { await AccessibilityProbe.watch(out: out, seconds: seconds); exit(0) }
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--ax-probe") { // developer run, read-only
            let out = URL(fileURLWithPath: CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : NSTemporaryDirectory())
            Task { await AccessibilityProbe.run(out: out); exit(0) }
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--guide-shots") { // developer run: PNGs of the windows for the site's guide
            let out = URL(fileURLWithPath: CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : NSTemporaryDirectory())
            Task { await GuideShots.run(coordinator, out: out); exit(0) }
            return
        }
        if CommandLine.arguments.contains("--completion-eval") { // developer run, see CompletionEval
            Task { await CompletionEval.run(); exit(0) }
            return
        }
        #endif
        // One Shotleaf at a time: two copies fight over the global hotkeys.
        let me = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != me }
        guard others.isEmpty else {
            NSApp.terminate(nil)
            return
        }
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--completion-live-test") { // developer run
            let args = CommandLine.arguments
            let text = args.count > i + 1 ? args[i + 1] : "Hi Anna, thanks for the update. I think we should"
            let out = URL(fileURLWithPath: args.count > i + 2 ? args[i + 2] : NSTemporaryDirectory())
            Task {
                await coordinator.start()
                await CompletionLiveTest.run(coordinator, text: text, out: out)
                exit(0)
            }
            return
        }
        #endif
        Task { await coordinator.start() }
    }

    /// Clicking the Dock icon (when shown) opens Settings — there's no main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { coordinator.openSettingsWindow() }
        return true
    }
}
