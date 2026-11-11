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
    let container: AppContainer
    var hotkeyTask: Task<Void, Never>?

    public internal(set) var permissions: [PermissionKind: PermissionStatus] = [:]
    public init(container: AppContainer = AppContainer()) {
        self.container = container
        self.clipboard = ClipboardHistory(recognizer: container.recognizer)
    }

    public func start() async {
        TempFolder.clearAll() // last run's drags, pastes and shares
        // ponytail: left by builds before "Recent Screenshots"; drop this line after a few releases.
        try? FileManager.default.removeItem(at: AppInfo.supportFolder.appendingPathComponent("last-capture.png"))
        applyDockPolicy()
        refreshPermissions()
        inlineCompletion.context.useScreen = container.settings.completionUsesScreen
        inlineCompletion.context.useClipboard = container.settings.completionUsesClipboard
        inlineCompletion.boldness = .init(container.settings.completionBoldness)
        inlineCompletion.quickFixes = container.settings.completionQuickFixes
        inlineCompletion.history.enabled = container.settings.completionLearnsStyle
        if container.settings.completionEnabled { inlineCompletion.start() }
        screenshots.allClosed = { [weak self] in
            // The setup guide's first screenshot: back to the guide, which closing the editor left behind other apps.
            if self?.onboarding?.isVisible == true { self?.onboarding?.show() } else { SupportAsk.askIfDue() }
        }
        screenshots.toSnippets = { [weak self] png in
            guard let self else { return nil }
            let folder = UserDefaults.standard.string(forKey: ClipboardPanelModel.folderKey).flatMap(UUID.init) // the folder last opened in the panel
            let saved = snippets.save(title: String(localized: "Screenshot"), text: "", pngs: [png], folder: folder)
            return snippets.folder(saved.folder)?.name
        }
        if isOn(.clipboard) { clipboard.start() }
        if isOn(.snippets) { expander.start() }
        Self.log.notice("startup permissions: \(String(describing: self.permissions), privacy: .public) bundle: \(Bundle.main.bundlePath, privacy: .public)")

        for action in HotkeyAction.allCases {
            registerHotkey(action, on: Tool.owning(action).map(isOn) ?? true)
        }

        // The setup guide: on first launch, when a tool that's on lacks its
        // permission, and back after the restart that follows granting one.
        let reopenGuide = UserDefaults.standard.bool(forKey: Self.reopenGuideKey)
        UserDefaults.standard.removeObject(forKey: Self.reopenGuideKey)
        let missing = Self.restartPermissions.filter { permissions[$0] != .granted }
        let needed = Tool.missing(on: Tool.allCases.filter(isOn), status: permissions)
        if !container.settings.onboardingCompleted || reopenGuide || !needed.isEmpty {
            container.settings.onboardingCompleted = true
            showOnboarding(resume: reopenGuide)
        }
        restartWhenGranted(missing)
        startUpdateChecks()
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

    let screenshots = ScreenshotWindows()

    // MARK: Clipboard

    let clipboard: ClipboardHistory
    let snippets = SnippetStore()
    @ObservationIgnored lazy var clipboardPanel: ClipboardPanelController = {
        let controller = ClipboardPanelController(history: clipboard, snippets: snippets)
        controller.openSnippetEditor = { [weak self] in self?.showSnippetEditor() }
        controller.openImage = { [weak self] in self?.screenshots.show($0, sound: false) }
        return controller
    }()

    public func showClipboard(snippets: Bool = false) { clipboardPanel.show(snippets: snippets) }

    @ObservationIgnored lazy var expander: SnippetExpander = {
        let expander = SnippetExpander(store: snippets)
        expander.ask = { [weak self] in self?.clipboardPanel.pick($0, .paste) }
        return expander
    }()

    var snippetWindow: NSWindow?

    /// The snippets editor (a window like the screenshot one).
    public func showSnippetEditor() {
        if snippetWindow?.isVisible != true {
            var window: FloatingPanel!
            // Closing lets go of the view, which holds the window: else every editor opened stays in memory.
            window = ScreenshotWindows.makePanel(SnippetEditorView(store: snippets, close: { window?.orderOut(nil); Task { window?.contentViewController = nil } }),
                                                 proposedWidth: 1000, resizable: true)
            window.level = .normal
            window.setContentSize(NSSize(width: 1000, height: max(window.frame.height, 680))) // room for the bottom bar in longer languages
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
    func deliver(_ shot: ImagePayload) {
        recentShots = ScreenshotWindows.remember(shot)
        shotsThisRun += 1
        SupportAsk.countShot()
        let entry = clipboard.addScreenshot(shot.data)
        let after = container.settings.afterCapture
        if after == .editor {
            screenshots.show(shot, edited: entry.map { id in { [weak self] png in self?.clipboard.updateImage(id, png: png) } })
            return
        }
        Sound.shutter()
        if after == .copy || after == .copyAndSave { ScreenshotWindows.copy(shot.data, own: entry != nil) }
        // The screen the shot came from (the picker was under the pointer), as the editor does.
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if after == .save || after == .copyAndSave { _ = ScreenshotWindows.save(shot.data, scale: screen?.backingScaleFactor ?? 2) }
        SupportAsk.askIfDue()
    }

    /// The last screenshot back in the editor (as it was taken).
    public func editLastScreenshot() {
        guard let last = recentShots.first else { NSSound.beep(); return }
        openRecent(last)
    }

    /// The newest captures, newest first (for the menu).
    public internal(set) var recentShots: [URL] = ScreenshotWindows.recent()

    public func openRecent(_ url: URL) {
        guard let shot = ScreenshotWindows.load(url) else { NSSound.beep(); return }
        screenshots.show(shot, sound: false)
    }

    /// Pictures from Finder (Open With), each in its own editor.
    public func openImages(_ urls: [URL]) {
        let shots = urls.compactMap(ScreenshotWindows.load)
        if shots.isEmpty { NSSound.beep() }
        NSApp.activate()
        for shot in shots { screenshots.show(shot, sound: false) }
    }

    /// "Combine Images…": pick two or more pictures; they open in the editor as one.
    public func combineImages() {
        let ask = NSOpenPanel()
        ask.allowedContentTypes = [.image]
        ask.allowsMultipleSelection = true
        ask.message = String(localized: "Pick two or more pictures to combine into one")
        ask.prompt = String(localized: "Combine")
        NSApp.activate()
        guard ask.runModal() == .OK else { return }
        let images = ask.urls.compactMap { NSBitmapImageRep(data: (try? Data(contentsOf: $0)) ?? Data())?.cgImage }
        guard images.count >= 2, let combined = Collage.make(images),
              let png = NSBitmapImageRep(cgImage: combined).representation(using: .png, properties: [:])
        else { NSSound.beep(); return }
        screenshots.show(ImagePayload(data: png, width: combined.width, height: combined.height), sound: false)
    }

    public func clearRecentShots() {
        try? FileManager.default.removeItem(at: ScreenshotWindows.recentFolder)
        recentShots = []
    }

    /// Everything Shotleaf keeps, then quit (a running app would write some of it back).
    public func deleteAllData() {
        clipboard.stop()
        expander.stop()
        inlineCompletion.stop()
        try? FileManager.default.removeItem(at: AppInfo.supportFolder) // history, snippets, recent shots, style
        ShotLinks.token = nil
        try? SMAppService.mainApp.unregister()
        Task {
            try? await EmbeddedModel.completion.delete()
            // Again: a save still in flight (a sensitive entry's expiry, a snippet) may have made the folder anew.
            try? FileManager.default.removeItem(at: AppInfo.supportFolder)
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

    var batchWindow: NSWindow?

    /// "Watermark Photos…": one watermark on many photos, in a window that
    /// looks like the screenshot window (leaf chrome, no system title bar).
    public func showBatchWatermark() {
        if batchWindow?.isVisible != true { batchWindow = nil } // closed: start over with no photos
        if batchWindow == nil {
            var window: FloatingPanel!
            let view = BatchWatermarkView(model: BatchWatermark(), close: { window?.orderOut(nil); Task { window?.contentViewController = nil } })
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
    public internal(set) var actionHotkeys: [HotkeyAction: HotkeyShortcut] = [:]

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

    public internal(set) var toolsOff: Set<Tool> = Tool.savedOff

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
    func registerHotkey(_ action: HotkeyAction, on: Bool) {
        let saved = on ? Self.savedHotkey(container.settings.hotkeyID(for: action.rawValue), default: action.defaultShortcut) : nil
        container.hotkeys.setShortcut(saved, for: action.rawValue)
        actionHotkeys[action] = container.hotkeys.shortcut(for: action.rawValue)
    }

    /// While recording a new shortcut the current ones must not fire (Carbon
    /// would swallow the key press and fire the action).
    public func pauseHotkey() { container.hotkeys.stop() }
    public func resumeHotkey() { container.hotkeys.start() }

    public internal(set) var modelState: EmbeddedState =
        EmbeddedModel.completion.isDownloaded ? .ready(bytes: EmbeddedModel.completion.sizeOnDisk) : .notDownloaded
    let inlineCompletion = InlineCompletion() // internal: the live test drives it
    /// A newer release than this one, once a check has found it (shown in the menu).
    public internal(set) var update: Updates.Release?
    /// An update is downloading and being checked (Shotleaf restarts when it's ready).
    public internal(set) var updating = false
    /// Whether Shotleaf starts at login. Real only for the installed, signed app.
    public internal(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    public internal(set) var launchAtLoginError: String?
    /// Screenshots taken since launch (the setup guide waits for the first one).
    public internal(set) var shotsThisRun = 0

    var updateTask: Task<Void, Never>?

    var onboarding: OnboardingWindowController?
}
