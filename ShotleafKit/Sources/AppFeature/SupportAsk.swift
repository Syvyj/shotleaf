import AppKit
import Core

/// Once, after real use (50 shots, or a month with at least 10): a quiet
/// "Enjoying Shotleaf?" with a way to support it. Never again after that.
@MainActor
enum SupportAsk {
    static let shotsKey = "supportAskShots", sinceKey = "supportAskSince", doneKey = "supportAskDone"

    nonisolated static func due(shots: Int, since: Date, now: Date = Date()) -> Bool {
        shots >= 50 || (shots >= 10 && now.timeIntervalSince(since) >= 30 * 86_400)
    }

    static func countShot(_ defaults: UserDefaults = .standard) {
        if defaults.object(forKey: sinceKey) == nil { defaults.set(Date(), forKey: sinceKey) }
        defaults.set(defaults.integer(forKey: shotsKey) + 1, forKey: shotsKey)
    }

    /// Asked when the user is between shots (the editor just closed), not in the middle of one.
    static func askIfDue(_ defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey),
              due(shots: defaults.integer(forKey: shotsKey), since: defaults.object(forKey: sinceKey) as? Date ?? Date())
        else { return }
        defaults.set(true, forKey: doneKey)
        let alert = NSAlert()
        alert.messageText = String(localized: "Enjoying Shotleaf?")
        alert.informativeText = String(localized: "Shotleaf is free and open source. Donations go towards Apple's developer licence ($99 a year), so Shotleaf installs without “Open Anyway”. Shotleaf asks this only once.")
        alert.addButton(withTitle: String(localized: "Support the Author"))
        alert.addButton(withTitle: String(localized: "No, Thanks"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(AppInfo.supportPage) }
    }
}
