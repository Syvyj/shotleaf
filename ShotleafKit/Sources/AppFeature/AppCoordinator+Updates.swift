import Core
import AppKit
import Observation
import SwiftUI
import ServiceManagement
import OSLog
import EmbeddedKit

/// Looking for a new version and updating to it.
extension AppCoordinator {
    // MARK: Updates

    public var checksForUpdates: Bool { container.settings.checksForUpdates }

    public func setChecksForUpdates(_ on: Bool) {
        container.settings.checksForUpdates = on
        startUpdateChecks()
    }

    /// At launch, then once a day while Shotleaf runs.
    func startUpdateChecks() {
        updateTask?.cancel()
        guard checksForUpdates else { update = nil; return }
        updateTask = Task { [weak self] in
            var launch = true
            while !Task.isCancelled {
                let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
                if launch || Date().timeIntervalSince(last) > 86_400, let release = try? await Updates.latest() {
                    UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
                    self?.update = Updates.isNewer(release.version, than: Updates.current) ? release : nil
                }
                launch = false
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    /// Downloads the update, checks it and restarts into it. Windows close with the
    /// restart, so it asks first (unless that was just asked). If it can't, the
    /// DMG can still be downloaded by hand.
    public func installUpdate(confirmed: Bool = false) {
        guard let release = update, !updating else { return }
        NSApp.activate(ignoringOtherApps: true)
        if !confirmed {
            let ask = NSAlert()
            ask.messageText = String(localized: "Update to Shotleaf \(release.version)?")
            ask.informativeText = String(localized: "Shotleaf downloads it, checks it and restarts in a few seconds. Open screenshots close, so copy or save what you need first.")
            ask.addButton(withTitle: String(localized: "Update"))
            ask.addButton(withTitle: String(localized: "Later"))
            guard ask.runModal() == .alertFirstButtonReturn else { return }
        }
        updating = true
        Task {
            do {
                Updates.swapAndRelaunch(try await Updates.prepare(release))
            } catch {
                updating = false
                Self.log.error("update failed: \(error.localizedDescription, privacy: .public)")
                let alert = NSAlert()
                alert.messageText = String(localized: "Couldn’t update Shotleaf")
                alert.informativeText = error.localizedDescription + " " + String(localized: "You can download the new version and drag it onto Applications yourself.")
                alert.addButton(withTitle: String(localized: "Download"))
                alert.addButton(withTitle: String(localized: "Cancel"))
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.download) }
            }
        }
    }

    /// "Check for Updates…": the answer right away, in a window.
    public func checkForUpdatesNow() {
        Task {
            guard let release = try? await Updates.latest() else { NSWorkspace.shared.open(AppInfo.releases); return }
            let newer = Updates.isNewer(release.version, than: Updates.current)
            update = newer ? release : nil
            let alert = NSAlert()
            NSApp.activate(ignoringOtherApps: true)
            if newer {
                alert.messageText = String(localized: "Shotleaf \(release.version) is out")
                alert.informativeText = String(localized: "You have \(Updates.current). Shotleaf downloads the new version, checks it and restarts; your settings and permissions stay.")
                alert.addButton(withTitle: String(localized: "Update"))
                alert.addButton(withTitle: String(localized: "Later"))
                if alert.runModal() == .alertFirstButtonReturn { installUpdate(confirmed: true) }
            } else {
                alert.messageText = String(localized: "Shotleaf is up to date")
                alert.informativeText = String(localized: "\(Updates.current) is the newest version.")
                alert.runModal()
            }
        }
    }
}
