import Core
import AppKit
import Observation
import SwiftUI
import ServiceManagement
import OSLog
import EmbeddedKit

/// The Dock icon, language, opening at login, the setup guide and permissions.
extension AppCoordinator {
    // MARK: Dock

    /// Dock icon on/off: a regular app vs. a menu-bar-only (accessory) app.
    public var showInDock: Bool { container.settings.showInDock }

    public func setShowInDock(_ show: Bool) {
        container.settings.showInDock = show
        applyDockPolicy()
        raiseSettingsWindow() // switching the policy sends the app's windows behind the others
    }

    func applyDockPolicy() {
        NSApp.setActivationPolicy(container.settings.showInDock ? .regular : .accessory)
    }

    /// The SwiftUI Settings scene, opened from AppKit (Dock click).
    public func openSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        raiseSettingsWindow()
    }

    /// A menu bar app isn't active, so its Settings window opens behind the
    /// others; bring it up once SwiftUI has made it (after a relaunch that takes a while).
    public func raiseSettingsWindow() {
        Task {
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(100))
                guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("Settings") == true })
                else { continue }
                // Not the polite activate(): after a relaunch macOS turns that down and the window stays behind.
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                return
            }
        }
    }

    // MARK: Language

    /// The app's own language ("en", "uk"), or nil to follow macOS.
    public var language: String? {
        (UserDefaults.standard.persistentDomain(forName: AppInfo.bundleID)?["AppleLanguages"] as? [String])?.first
    }

    /// Takes effect on the next launch, so restart now and come back to Settings.
    public func setLanguage(_ code: String?) {
        guard code != language else { return }
        if let code { UserDefaults.standard.set([code], forKey: "AppleLanguages") }
        else { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
        UserDefaults.standard.set(true, forKey: Self.reopenSettingsKey)
        Self.relaunch()
    }

    static let reopenSettingsKey = "reopenSettings"

    // MARK: Launch at login

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Onboarding


    /// The setup guide: shown on first launch, and from the menu any time (from
    /// its start). `resume`: back on the page it was on, after a restart for a permission.
    public func showOnboarding(resume: Bool = false) {
        if !resume { UserDefaults.standard.removeObject(forKey: OnboardingView.pageKey) }
        let controller = onboarding ?? OnboardingWindowController { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(OnboardingView(coordinator: self))
        }
        onboarding = controller
        controller.show()
    }

    public func closeOnboarding() {
        UserDefaults.standard.removeObject(forKey: OnboardingView.pageKey)
        onboarding?.close()
    }

    // MARK: Permissions (for Settings)

    public func refreshPermissions() {
        for kind in PermissionKind.allCases {
            permissions[kind] = container.permissions.status(kind)
        }
    }

    static let log = Logger(subsystem: "dev.syvyj.shotleaf", category: "permissions")
    static let reopenGuideKey = "reopenSetupGuide"

    /// What only works in a process that started with the permission on: the
    /// keyboard taps (completion, snippets, pasting) and screen capture.
    static let restartPermissions: [PermissionKind] = [.accessibility, .screenRecording]

    /// Watches the permissions missing at launch; once the user grants one,
    /// restarts so it takes effect (macOS doesn't always offer to).
    func restartWhenGranted(_ missing: [PermissionKind]) {
        guard !missing.isEmpty else { return }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                guard let granted = missing.first(where: { self.container.permissions.status($0) == .granted }) else { continue }
                Self.log.notice("\(String(describing: granted), privacy: .public) granted — restarting")
                if self.onboarding?.isVisible == true { UserDefaults.standard.set(true, forKey: Self.reopenGuideKey) }
                Self.relaunch()
                return
            }
        }
    }

    /// Opens a fresh copy once this one has quit (two copies can't run at once).
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done; open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    public func request(_ kind: PermissionKind) async {
        await container.permissions.request(kind)
        refreshPermissions()
    }

    public func openSettings(for kind: PermissionKind) {
        container.permissions.openSystemSettings(for: kind)
    }
}
