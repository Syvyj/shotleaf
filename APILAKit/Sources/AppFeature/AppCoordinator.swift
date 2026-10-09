import Core
import ActionKit
import InferenceKit
import AppKit
import Observation
import SwiftUI
import ServiceManagement
import OSLog
import EmbeddedKit

/// Orchestrates the full vertical slice — Hotkey → ContextKit → ActionRunner →
/// InferenceKit → Floating Panel → Clipboard/Replace. Pure wiring: it owns no
/// business logic (that lives in the Kits) and no UI flow (that lives in
/// PanelViewModel).
@MainActor
@Observable
public final class AppCoordinator {
    private let container: AppContainer
    private let panelVM: PanelViewModel
    private var panel: FloatingPanelController?
    private var hotkeyTask: Task<Void, Never>?

    public private(set) var permissions: [PermissionKind: PermissionStatus] = [:]
    /// e.g. "LM Studio · local-model", or "Mock" when the provider is unreachable.
    public private(set) var currentProviderName: String = "—"
    /// Why the chosen provider isn't used (nil when it is healthy).
    public private(set) var providerProblem: String?
    /// False when the global shortcut couldn't be registered (e.g. taken by another app).
    public private(set) var hotkeyRegistered = true

    public struct HistoryEntry: Identifiable, Equatable {
        public let id = UUID()
        public let title: String
        public let output: String
        public let date: Date
    }
    /// Recent results, newest first. Memory only — results may contain private
    /// text, so nothing is written to disk.
    public private(set) var history: [HistoryEntry] = []
    static let historyLimit = 10

    public init(container: AppContainer = AppContainer()) {
        self.container = container
        let inserter = ResultInserter(clipboard: container.clipboard)
        let permissions = container.permissions
        self.panelVM = PanelViewModel(
            runner: container.actionRunner,
            inserter: inserter,
            actions: [],
            accessibilityGranted: { permissions.status(.accessibility) == .granted },
            captureScreen: { [capture = container.capture] in try await capture.captureRegion() }
        )
        applyTranslateSettings()
        panelVM.onResult = { [weak self] title, output in
            self?.remember(title: title, output: output)
        }
    }

    func remember(title: String, output: String) {
        history.insert(HistoryEntry(title: title, output: output, date: Date()), at: 0)
        history = Array(history.prefix(Self.historyLimit))
    }

    public func copyFromHistory(_ entry: HistoryEntry) {
        Task { try? await container.clipboard.writeText(entry.output) }
    }

    public func clearHistory() { history = [] }

    public func start() async {
        applyDockPolicy()
        await container.bootstrap()
        await refreshProvider()
        refreshPermissions()
        inlineCompletion.context.useScreen = container.settings.completionUsesScreen
        inlineCompletion.context.useClipboard = container.settings.completionUsesClipboard
        inlineCompletion.boldness = .init(container.settings.completionBoldness)
        inlineCompletion.quickFixes = container.settings.completionQuickFixes
        inlineCompletion.history.enabled = container.settings.completionLearnsStyle
        if container.settings.completionEnabled { inlineCompletion.start() }
        Self.log.notice("startup permissions: \(String(describing: self.permissions), privacy: .public) bundle: \(Bundle.main.bundlePath, privacy: .public)")

        let panel = FloatingPanelController { [weak self] in
            if let self { return AnyView(PanelView(vm: self.panelVM)) }
            return AnyView(EmptyView())
        }
        self.panel = panel
        panelVM.onClose = { [weak self] in self?.panel?.hide() }
        panelVM.onHide = { [weak self] in self?.panel?.hide() }
        screenshots.onText = { [weak self] image in
            self?.openPanelForScreenshot()
            self?.panelVM.useScreenshot(image, ask: false)
        }
        screenshots.onAsk = { [weak self] image in
            self?.openPanelForScreenshot()
            self?.panelVM.useScreenshot(image, ask: true)
        }
        panelVM.onShow = { [weak self] in self?.panel?.show() }

        let hotkeys = container.hotkeys
        hotkeyRegistered = hotkeys.setShortcut(.with(id: container.settings.hotkey), for: Self.panelHotkey)
        hotkey = hotkeys.shortcut(for: Self.panelHotkey) ?? .default
        for action in HotkeyAction.allCases {
            let saved = Self.savedHotkey(container.settings.hotkeyID(for: action.rawValue), default: action.defaultShortcut)
            hotkeys.setShortcut(saved, for: action.rawValue)
            actionHotkeys[action] = hotkeys.shortcut(for: action.rawValue)
        }

        // Auto-shown once; afterwards it lives in the menu ("Setup Guide…").
        if !container.settings.onboardingCompleted {
            container.settings.onboardingCompleted = true
            showOnboarding()
        }
        hotkeyTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.container.hotkeys.events {
                switch event.identifier {
                case HotkeyAction.screenshotText.rawValue: self.screenshotFromMenu(ask: false)
                case HotkeyAction.capture.rawValue: self.takeScreenshot()
                case HotkeyAction.scrolling.rawValue: self.takeScrollingScreenshot()
                default: await self.present()
                }
            }
        }
    }

    /// Capture context (while the source app is still focused), then show the panel.
    public func present() async {
        let requirements = ContextRequirements(needsSelectedText: true, needsClipboard: true)
        let snapshot = (try? await container.context.snapshot(requirements: requirements))
            ?? ContextSnapshot(capturedAt: Date())
        let sourceApp = NSWorkspace.shared.frontmostApplication
        panelVM.present(snapshot: snapshot, sourceApp: sourceApp)
        panel?.show()
        // Detached from the hotkey loop, so a slow/hung endpoint never delays the panel.
        Task { await refreshProvider() }
    }

    public func refreshProvider() async {
        let kind = container.providerKind.displayName
        let health = await container.refreshProvider()
        switch health {
        case .healthy:
            let model = container.providerModel
            currentProviderName = model.isEmpty ? kind : "\(kind) · \(model)"
            providerProblem = nil
        case .unhealthy(let reason):
            currentProviderName = String(localized: "Mock (\(kind) unavailable)")
            providerProblem = reason
        }
        panelVM.isMockProvider = health != .healthy
        panelVM.providerName = currentProviderName
    }

    public func openFromMenu() { Task { await present() } }

    // MARK: Screenshots

    private let screenshots = ScreenshotWindows()

    /// Shottr-style: pick a region → preview window (copy, save, pin, drag, OCR, ask).
    /// `delay`: seconds to wait first (with a countdown), to open a menu or
    /// tooltip that should be in the shot.
    public func takeScreenshot(delay: Int = 0) {
        Task {
            if delay > 0 { await screenshots.countdown(delay) }
            do {
                screenshots.show(try await container.capture.captureRegion())
            } catch AppError.cancelled {
                // Esc in the picker: nothing to show.
            } catch {
                openPanelForScreenshot()
                panelVM.showError(error)
            }
        }
    }

    /// Scrolling screenshot: pick an area, scroll it, press Done.
    public func takeScrollingScreenshot() {
        Task {
            do {
                screenshots.show(try await container.capture.captureScrolling())
            } catch AppError.cancelled {
            } catch {
                openPanelForScreenshot()
                panelVM.showError(error)
            }
        }
    }

    /// The panel, opened fresh for working on a screenshot (no text selection).
    private func openPanelForScreenshot() {
        panelVM.present(snapshot: ContextSnapshot(capturedAt: Date()), sourceApp: NSWorkspace.shared.frontmostApplication)
        panel?.show()
    }

    /// Menu entry points for screenshots: no selection needed. The panel opens
    /// straight into the region picker.
    public func screenshotFromMenu(ask: Bool) {
        panelVM.present(snapshot: ContextSnapshot(capturedAt: Date()), sourceApp: NSWorkspace.shared.frontmostApplication)
        panelVM.startScreenshot(ask: ask, reopenOnCancel: false)
    }

    // MARK: Settings

    static let panelHotkey = "panel"

    /// The active shortcuts (stored, so SwiftUI observes changes).
    public private(set) var hotkey: HotkeyShortcut = .default
    /// Shortcuts of the other actions; missing = off.
    public private(set) var actionHotkeys: [HotkeyAction: HotkeyShortcut] = [:]

    /// Settings value → shortcut: nil = never set (default on), "off" = disabled.
    static func savedHotkey(_ saved: String?, default fallback: HotkeyShortcut) -> HotkeyShortcut? {
        switch saved {
        case nil: fallback
        case "off": nil
        case let id: .with(id: id)
        }
    }

    /// Returns false (and keeps the old one) if the shortcut is taken.
    public func setHotkey(_ shortcut: HotkeyShortcut) -> Bool {
        let hotkeys = container.hotkeys
        let ok = hotkeys.setShortcut(shortcut, for: Self.panelHotkey)
        if ok { container.settings.hotkey = shortcut.id }
        hotkeyRegistered = ok || hotkeyRegistered
        hotkey = hotkeys.shortcut(for: Self.panelHotkey) ?? .default
        hotkeys.start() // re-register any paused while recording
        return ok
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

    /// While recording a new shortcut the current ones must not fire (Carbon
    /// would swallow the key press and open the panel).
    public func pauseHotkey() { container.hotkeys.stop() }
    public func resumeHotkey() { container.hotkeys.start() }

    public struct ProviderSettings: Equatable {
        public var kind: ProviderKind
        public var baseURL: String
        public var apiKey: String
        public var model: String
        /// Send screenshots as images (vision model) instead of their OCR text.
        public var supportsVision: Bool
    }

    public func savedProviderSettings() -> ProviderSettings {
        providerSettings(for: container.providerKind, keepSavedURLAndModel: true)
    }

    /// Form values for `kind`: its saved key, and the saved URL/model only if
    /// `kind` is the saved one (otherwise that kind's defaults).
    public func providerSettings(for kind: ProviderKind, keepSavedURLAndModel: Bool) -> ProviderSettings {
        let settings = container.settings
        let isSaved = keepSavedURLAndModel && kind == container.providerKind
        return ProviderSettings(
            kind: kind,
            baseURL: (isSaved ? settings.baseURL : nil) ?? kind.defaultBaseURL.absoluteString,
            apiKey: settings.apiKey(for: kind.rawValue) ?? "",
            model: (isSaved ? settings.model : nil) ?? kind.defaultModel,
            supportsVision: (isSaved ? settings.supportsVision : nil) ?? kind.capabilities.supportsVision
        )
    }

    public func saveProvider(_ draft: ProviderSettings) async {
        let settings = container.settings
        settings.providerKind = draft.kind.rawValue
        let url = draft.baseURL.trimmingCharacters(in: .whitespaces)
        settings.baseURL = url.isEmpty || url == draft.kind.defaultBaseURL.absoluteString ? nil : url
        settings.model = draft.model.trimmingCharacters(in: .whitespaces)
        settings.supportsVision = draft.supportsVision == draft.kind.capabilities.supportsVision ? nil : draft.supportsVision
        settings.setAPIKey(draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: draft.kind.rawValue)
        container.applyProviderSettings()
        await refreshProvider()
    }

    // MARK: Built-in model

    public enum EmbeddedState: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready(bytes: Int64)
        case failed(String)
    }

    /// The two built-in models: chat (actions, screenshots) and completion.
    public enum BuiltInModel: Hashable, Sendable {
        case chat, completion
        var model: EmbeddedModel { self == .chat ? .shared : .completion }
    }

    public private(set) var modelStates: [BuiltInModel: EmbeddedState] = [
        .chat: AppCoordinator.initialState(.chat), .completion: AppCoordinator.initialState(.completion),
    ]

    private static func initialState(_ which: BuiltInModel) -> EmbeddedState {
        which.model.isDownloaded ? .ready(bytes: which.model.sizeOnDisk) : .notDownloaded
    }

    public func state(of which: BuiltInModel) -> EmbeddedState { modelStates[which] ?? .notDownloaded }

    /// Downloads (and loads) a built-in model, reporting progress to Settings.
    public func download(_ which: BuiltInModel) {
        if case .downloading = state(of: which) { return }
        modelStates[which] = .downloading(0)
        Task {
            do {
                _ = try await which.model.load { fraction in
                    Task { @MainActor [weak self] in
                        if case .downloading = self?.state(of: which) { self?.modelStates[which] = .downloading(fraction) }
                    }
                }
                modelStates[which] = .ready(bytes: which.model.sizeOnDisk)
            } catch {
                modelStates[which] = .failed(error.localizedDescription)
            }
            await refreshProvider()
        }
    }

    public func delete(_ which: BuiltInModel) {
        Task {
            do {
                try await which.model.delete()
                modelStates[which] = .notDownloaded
            } catch {
                modelStates[which] = .failed(error.localizedDescription)
            }
            await refreshProvider()
        }
    }

    public func availableModels(for draft: ProviderSettings) async throws -> [String] {
        try await container.availableModels(
            kind: draft.kind,
            baseURL: URL(string: draft.baseURL),
            apiKey: draft.apiKey.isEmpty ? nil : draft.apiKey
        )
    }

    public var translateLanguages: (target: String, fallback: String) {
        (container.settings.translateTarget, container.settings.translateFallback)
    }

    public func saveTranslate(target: String, fallback: String) {
        container.settings.translateTarget = target
        container.settings.translateFallback = fallback
        applyTranslateSettings()
    }

    private func applyTranslateSettings() {
        panelVM.setActions(BuiltInActions.inferenceActions(
            translateTo: container.settings.translateTarget,
            otherwise: container.settings.translateFallback
        ))
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
        NSApp.activate()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    // MARK: Launch at login

    /// Whether APILA starts at login. Real only for the installed, signed app.
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

    private static let log = Logger(subsystem: "app.apila.APILA", category: "permissions")

    public func request(_ kind: PermissionKind) async {
        await container.permissions.request(kind)
        refreshPermissions()
    }

    public func openSettings(for kind: PermissionKind) {
        container.permissions.openSystemSettings(for: kind)
    }
}
