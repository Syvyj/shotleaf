import Core
import AppKit
import Observation
import SwiftUI
import ServiceManagement
import OSLog
import EmbeddedKit

/// Wires Shotleaf together: global hotkeys → screenshots / text from a
/// screenshot / scrolling capture, inline completion and its model, settings,
/// permissions, onboarding. Pure wiring: the logic lives in the Kits and views.
@MainActor
@Observable
public final class AppCoordinator {
    private let container: AppContainer
    private var hotkeyTask: Task<Void, Never>?

    public private(set) var permissions: [PermissionKind: PermissionStatus] = [:]
    public init(container: AppContainer = AppContainer()) {
        self.container = container
        self.clipboard = ClipboardHistory(recognizer: container.recognizer)
    }

    public func start() async {
        for name in ScreenshotWindows.tempFolders { // last run's drags, pastes and shares
            try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent(name))
        }
        applyDockPolicy()
        refreshPermissions()
        inlineCompletion.context.useScreen = container.settings.completionUsesScreen
        inlineCompletion.context.useClipboard = container.settings.completionUsesClipboard
        inlineCompletion.boldness = .init(container.settings.completionBoldness)
        inlineCompletion.quickFixes = container.settings.completionQuickFixes
        inlineCompletion.history.enabled = container.settings.completionLearnsStyle
        if container.settings.completionEnabled { inlineCompletion.start() }
        screenshots.toSnippets = { [weak self] png in
            guard let self else { return nil }
            let folder = UserDefaults.standard.string(forKey: "snippetFolder").flatMap(UUID.init) // the folder last opened in the panel
            let saved = snippets.save(title: String(localized: "Screenshot"), text: "", pngs: [png], folder: folder)
            return snippets.folder(saved.folder)?.name
        }
        if isOn(.clipboard) { clipboard.start() }
        if isOn(.snippets) { expander.start() }
        Self.log.notice("startup permissions: \(String(describing: self.permissions), privacy: .public) bundle: \(Bundle.main.bundlePath, privacy: .public)")

        for action in HotkeyAction.allCases {
            registerHotkey(action, on: Tool.owning(action).map(isOn) ?? true)
        }

        // The setup guide: on first launch, whenever a permission is missing,
        // and back after the restart that follows granting one.
        let reopenGuide = UserDefaults.standard.bool(forKey: Self.reopenGuideKey)
        UserDefaults.standard.removeObject(forKey: Self.reopenGuideKey)
        let missing = Self.restartPermissions.filter { permissions[$0] != .granted }
        if !container.settings.onboardingCompleted || reopenGuide || !missing.isEmpty {
            container.settings.onboardingCompleted = true
            showOnboarding()
        }
        restartWhenGranted(missing)
        if UserDefaults.standard.bool(forKey: Self.reopenSettingsKey) {
            UserDefaults.standard.removeObject(forKey: Self.reopenSettingsKey)
            openSettingsWindow()
        }
        hotkeyTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.container.hotkeys.events {
                switch event.identifier {
                case HotkeyAction.screenshotText.rawValue: self.textFromScreenshot()
                case HotkeyAction.capture.rawValue: self.takeScreenshot()
                case HotkeyAction.scrolling.rawValue: self.takeScrollingScreenshot()
                case HotkeyAction.editLast.rawValue: self.editLastScreenshot()
                case HotkeyAction.editClipboard.rawValue: self.editClipboardImage()
                case HotkeyAction.clipboard.rawValue:
                    // While a queue runs, the panel's key pastes its next entry.
                    if self.clipboardPanel.isQueueing { self.clipboardPanel.pasteNextQueued() } else { self.clipboardPanel.toggle() }
                case HotkeyAction.snippets.rawValue: self.clipboardPanel.toggle(snippets: true)
                default: break
                }
            }
        }
    }

    // MARK: Screenshots

    private let screenshots = ScreenshotWindows()

    // MARK: Clipboard

    let clipboard: ClipboardHistory
    let snippets = SnippetStore()
    @ObservationIgnored private lazy var clipboardPanel: ClipboardPanelController = {
        let controller = ClipboardPanelController(history: clipboard, snippets: snippets)
        controller.openSnippetEditor = { [weak self] in self?.showSnippetEditor() }
        controller.openImage = { [weak self] in self?.screenshots.show($0, sound: false) }
        return controller
    }()

    public func showClipboard(snippets: Bool = false) { clipboardPanel.show(snippets: snippets) }

    @ObservationIgnored private lazy var expander: SnippetExpander = {
        let expander = SnippetExpander(store: snippets)
        expander.ask = { [weak self] in self?.clipboardPanel.pick($0, .paste) }
        return expander
    }()

    private var snippetWindow: NSWindow?

    /// The snippets editor (a window like the screenshot one).
    public func showSnippetEditor() {
        if snippetWindow?.isVisible != true {
            var window: FloatingPanel!
            window = ScreenshotWindows.makePanel(SnippetEditorView(store: snippets, close: { window?.orderOut(nil) }),
                                                 proposedWidth: 1000, resizable: true)
            window.level = .normal
            window.setContentSize(NSSize(width: 1000, height: max(window.frame.height, 620)))
            window.center()
            snippetWindow = window
        }
        NSApp.activate()
        snippetWindow?.makeKeyAndOrderFront(nil)
    }

    /// From the menu: the entry goes onto the clipboard and into the app in front.
    public func pasteFromHistory(_ id: UUID) {
        guard let item = clipboard.items.first(where: { $0.id == id }) else { return }
        clipboardPanel.pick(item, .paste)
    }

    public func cancelPasteQueue() { clipboardPanel.cancelQueue() }

    public func pauseClipboard(minutes: Int?) {
        clipboard.pausedUntil = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
    }

    /// Pick a region → preview window (copy, save, pin, drag, Live Text).
    /// `delay`: seconds to wait first (with a countdown), to open a menu or
    /// tooltip that should be in the shot; nil = the default from Settings.
    public func takeScreenshot(delay: Int? = nil) {
        Task {
            let delay = delay ?? container.settings.captureDelay
            if delay > 0 { await screenshots.countdown(delay) }
            do {
                deliver(try await container.capture.captureRegion())
            } catch AppError.cancelled {
                // Esc in the picker: nothing to show.
            } catch {
                screenshots.showProblem(error)
            }
        }
    }

    /// Text from a screenshot: pick a region → its text (on-device OCR) in a
    /// small window to select, fix and copy.
    public func textFromScreenshot() {
        Task {
            do {
                let shot = try await container.capture.captureRegion()
                screenshots.showText(try await container.recognizer.recognizeText(in: shot))
            } catch AppError.cancelled {
            } catch {
                screenshots.showProblem(error)
            }
        }
    }

    /// Scrolling screenshot: pick an area, scroll it, press Done.
    public func takeScrollingScreenshot() {
        Task {
            do {
                deliver(try await container.capture.captureScrolling())
            } catch AppError.cancelled {
            } catch {
                screenshots.showProblem(error)
            }
        }
    }

    /// A new shot: into the editor, or straight to the clipboard / a file
    /// (Settings → Screenshots). Kept for "Edit Last Screenshot" either way.
    private func deliver(_ shot: ImagePayload) {
        recentShots = ScreenshotWindows.remember(shot)
        let entry = clipboard.addScreenshot(shot.data)
        let after = container.settings.afterCapture
        if after == .editor {
            screenshots.show(shot, edited: entry.map { id in { [weak self] png in self?.clipboard.updateImage(id, png: png) } })
            return
        }
        Sound.shutter()
        if after == .copy || after == .copyAndSave { ScreenshotWindows.copy(shot.data, own: entry != nil) }
        if after == .save || after == .copyAndSave { _ = ScreenshotWindows.save(shot.data, scale: NSScreen.main?.backingScaleFactor ?? 2) }
    }

    /// The last screenshot back in the editor (as it was taken).
    public func editLastScreenshot() {
        guard let last = recentShots.first else { NSSound.beep(); return }
        openRecent(last)
    }

    /// The newest captures, newest first (for the menu).
    public private(set) var recentShots: [URL] = ScreenshotWindows.recent()

    public func openRecent(_ url: URL) {
        guard let shot = ScreenshotWindows.load(url) else { NSSound.beep(); return }
        screenshots.show(shot, sound: false)
    }

    public func clearRecentShots() {
        try? FileManager.default.removeItem(at: ScreenshotWindows.recentFolder)
        recentShots = []
    }

    /// Everything Shotleaf keeps, then quit (a running app would write some of it back).
    public func deleteAllData() {
        clipboard.stop()
        try? FileManager.default.removeItem(at: AppInfo.supportFolder) // history, snippets, recent shots, style
        ShotLinks.token = nil
        try? SMAppService.mainApp.unregister()
        Task {
            try? await EmbeddedModel.completion.delete()
            UserDefaults.standard.removePersistentDomain(forName: AppInfo.bundleID)
            NSApp.terminate(nil)
        }
    }

    public func showRecentFolder() {
        NSWorkspace.shared.activateFileViewerSelecting(recentShots.isEmpty ? [ScreenshotWindows.recentFolder] : [recentShots[0]])
    }

    /// An image from the clipboard in the editor, to mark up like a screenshot.
    public func editClipboardImage() {
        guard let shot = ScreenshotWindows.clipboardImage() else { NSSound.beep(); return }
        screenshots.show(shot, sound: false)
    }

    private var batchWindow: NSWindow?

    /// "Watermark Photos…": one watermark on many photos, in a window that
    /// looks like the screenshot window (leaf chrome, no system title bar).
    public func showBatchWatermark() {
        if batchWindow?.isVisible != true { batchWindow = nil } // closed: start over with no photos
        if batchWindow == nil {
            var window: FloatingPanel!
            let view = BatchWatermarkView(model: BatchWatermark(), close: { window?.orderOut(nil) })
            window = ScreenshotWindows.makePanel(view, proposedWidth: 1100, resizable: true)
            window.level = .normal // a longer task: other apps may go on top of it
            window.setContentSize(NSSize(width: 1100, height: max(window.frame.height, 740)))
            window.center()
            batchWindow = window
        }
        NSApp.activate()
        batchWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Settings

    /// The actions' shortcuts; missing = off.
    public private(set) var actionHotkeys: [HotkeyAction: HotkeyShortcut] = [:]

    /// Settings value → shortcut: nil = never set (default on), "off" = disabled.
    static func savedHotkey(_ saved: String?, default fallback: HotkeyShortcut) -> HotkeyShortcut? {
        switch saved {
        case nil: fallback
        case "off": nil
        case let id: .with(id: id)
        }
    }

    /// nil turns the action's hotkey off. False if the shortcut is taken.
    public func setHotkey(_ shortcut: HotkeyShortcut?, for action: HotkeyAction) -> Bool {
        let hotkeys = container.hotkeys
        let ok = hotkeys.setShortcut(shortcut, for: action.rawValue)
        if ok { container.settings.setHotkeyID(shortcut?.id ?? "off", for: action.rawValue) }
        actionHotkeys[action] = hotkeys.shortcut(for: action.rawValue)
        hotkeys.start()
        return ok
    }

    // MARK: Tools

    public private(set) var toolsOff: Set<Tool> = Tool.savedOff

    public func isOn(_ tool: Tool) -> Bool { tool == .completion ? completionEnabled : !toolsOff.contains(tool) }

    public func setTool(_ tool: Tool, on: Bool) {
        if tool == .completion { setCompletion(on); return }
        if on { toolsOff.remove(tool) } else { toolsOff.insert(tool) }
        UserDefaults.standard.set(toolsOff.map(\.rawValue), forKey: Tool.offKey)
        for action in tool.actions { registerHotkey(action, on: on) }
        switch tool {
        case .clipboard: if on { clipboard.start() } else { clipboard.stop() }
        case .snippets: if on { expander.start() } else { expander.stop() }
        default: break
        }
    }

    /// The saved shortcut while the action's tool is on; none while it's off (the choice is kept).
    private func registerHotkey(_ action: HotkeyAction, on: Bool) {
        let saved = on ? Self.savedHotkey(container.settings.hotkeyID(for: action.rawValue), default: action.defaultShortcut) : nil
        container.hotkeys.setShortcut(saved, for: action.rawValue)
        actionHotkeys[action] = container.hotkeys.shortcut(for: action.rawValue)
    }

    /// While recording a new shortcut the current ones must not fire (Carbon
    /// would swallow the key press and fire the action).
    public func pauseHotkey() { container.hotkeys.stop() }
    public func resumeHotkey() { container.hotkeys.start() }

    // MARK: Completion model

    public enum EmbeddedState: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready(bytes: Int64)
        case failed(String)
    }

    public private(set) var modelState: EmbeddedState =
        EmbeddedModel.completion.isDownloaded ? .ready(bytes: EmbeddedModel.completion.sizeOnDisk) : .notDownloaded

    /// Downloads (and loads) the completion model, reporting progress to Settings.
    /// What the download needs on disk (the model is about 3.6 GB), with room to spare.
    static let modelSpace: Int64 = 4_500_000_000

    public func downloadModel() {
        if case .downloading = modelState { return }
        let home = URL(fileURLWithPath: NSHomeDirectory())
        if let free = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           free < Self.modelSpace - EmbeddedModel.completion.sizeOnDisk {
            let need = ByteCountFormatter.string(fromByteCount: Self.modelSpace, countStyle: .file)
            let have = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
            modelState = .failed(String(localized: "Not enough free space: the model needs about \(need), \(have) is free."))
            return
        }
        modelState = .downloading(0)
        Task {
            do {
                _ = try await EmbeddedModel.completion.load { fraction in
                    Task { @MainActor [weak self] in
                        if case .downloading = self?.modelState { self?.modelState = .downloading(fraction) }
                    }
                }
                modelState = .ready(bytes: EmbeddedModel.completion.sizeOnDisk)
            } catch {
                guard case .downloading = modelState else { return } // cancelled
                modelState = .failed(error.localizedDescription)
            }
        }
    }

    public func cancelModelDownload() {
        modelState = .notDownloaded
        Task { await EmbeddedModel.completion.cancel() }
    }

    public func deleteModel() {
        Task {
            do {
                try await EmbeddedModel.completion.delete()
                modelState = .notDownloaded
            } catch {
                modelState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Inline completion

    let inlineCompletion = InlineCompletion() // internal: the live test drives it

    public var completionEnabled: Bool { container.settings.completionEnabled }

    public var completionUsesScreen: Bool { container.settings.completionUsesScreen }
    public var completionUsesClipboard: Bool { container.settings.completionUsesClipboard }

    public func setCompletionContext(screen: Bool? = nil, clipboard: Bool? = nil) {
        if let screen { container.settings.completionUsesScreen = screen; inlineCompletion.context.useScreen = screen }
        if let clipboard { container.settings.completionUsesClipboard = clipboard; inlineCompletion.context.useClipboard = clipboard }
    }

    public var completionBoldness: Double { container.settings.completionBoldness }
    public var completionQuickFixes: Bool { container.settings.completionQuickFixes }
    public var completionLearnsStyle: Bool { container.settings.completionLearnsStyle }

    public func setCompletionBoldness(_ value: Double) {
        container.settings.completionBoldness = value
        inlineCompletion.boldness = .init(value)
    }

    public func setCompletionQuickFixes(_ on: Bool) {
        container.settings.completionQuickFixes = on
        inlineCompletion.quickFixes = on
    }

    public func setCompletionLearnsStyle(_ on: Bool) {
        container.settings.completionLearnsStyle = on
        inlineCompletion.history.enabled = on
    }

    public func forgetWritingStyle() { inlineCompletion.history.forget() }

    public func setCompletion(_ on: Bool) {
        container.settings.completionEnabled = on
        if on { inlineCompletion.start() } else { inlineCompletion.stop() }
    }

    // MARK: Dock

    /// Dock icon on/off: a regular app vs. a menu-bar-only (accessory) app.
    public var showInDock: Bool { container.settings.showInDock }

    public func setShowInDock(_ show: Bool) {
        container.settings.showInDock = show
        applyDockPolicy()
    }

    private func applyDockPolicy() {
        NSApp.setActivationPolicy(container.settings.showInDock ? .regular : .accessory)
    }

    /// The SwiftUI Settings scene, opened from AppKit (Dock click).
    public func openSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        raiseSettingsWindow()
    }

    /// A menu bar app isn't active, so its Settings window opens behind the
    /// others; bring it up once SwiftUI has made it.
    public func raiseSettingsWindow() {
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            NSApp.activate()
            NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true }?.makeKeyAndOrderFront(nil)
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

    private static let reopenSettingsKey = "reopenSettings"

    // MARK: Launch at login

    /// Whether Shotleaf starts at login. Real only for the installed, signed app.
    public private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    public private(set) var launchAtLoginError: String?

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

    private var onboarding: OnboardingWindowController?

    /// The setup guide: shown once on first launch, and from the menu any time.
    public func showOnboarding() {
        let controller = onboarding ?? OnboardingWindowController { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(OnboardingView(coordinator: self))
        }
        onboarding = controller
        controller.show()
    }

    public func closeOnboarding() { onboarding?.close() }

    // MARK: Permissions (for Settings)

    public func refreshPermissions() {
        for kind in PermissionKind.allCases {
            permissions[kind] = container.permissions.status(kind)
        }
    }

    private static let log = Logger(subsystem: "dev.syvyj.shotleaf", category: "permissions")
    private static let reopenGuideKey = "reopenSetupGuide"

    /// What only works in a process that started with the permission on: the
    /// keyboard taps (completion, snippets, pasting) and screen capture.
    static let restartPermissions: [PermissionKind] = [.accessibility, .screenRecording]

    /// Watches the permissions missing at launch; once the user grants one,
    /// restarts so it takes effect (macOS doesn't always offer to).
    private func restartWhenGranted(_ missing: [PermissionKind]) {
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
