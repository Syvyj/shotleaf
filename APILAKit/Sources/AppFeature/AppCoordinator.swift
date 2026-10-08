import Core
import ActionKit
import InferenceKit
import AppKit
import Observation
import SwiftUI
import ServiceManagement
import OSLog

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
        Self.log.notice("startup permissions: \(String(describing: self.permissions), privacy: .public) bundle: \(Bundle.main.bundlePath, privacy: .public)")

        let panel = FloatingPanelController { [weak self] in
            if let self { return AnyView(PanelView(vm: self.panelVM)) }
            return AnyView(EmptyView())
        }
        self.panel = panel
        panelVM.onClose = { [weak self] in self?.panel?.hide() }
        panelVM.onHide = { [weak self] in self?.panel?.hide() }
        panelVM.onShow = { [weak self] in self?.panel?.show() }

        let hotkeys = container.hotkeys
        hotkeyRegistered = hotkeys.setShortcut(.with(id: container.settings.hotkey), for: Self.panelHotkey)
        hotkey = hotkeys.shortcut(for: Self.panelHotkey) ?? .default
        hotkeys.setShortcut(Self.savedScreenshotHotkey(container.settings.screenshotHotkey), for: Self.screenshotHotkeyID)
        screenshotHotkey = hotkeys.shortcut(for: Self.screenshotHotkeyID)

        // Auto-shown once; afterwards it lives in the menu ("Setup Guide…").
        if !container.settings.onboardingCompleted {
            container.settings.onboardingCompleted = true
            showOnboarding()
        }
        hotkeyTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.container.hotkeys.events {
                switch event.identifier {
                case Self.screenshotHotkeyID: self.screenshotFromMenu(ask: false)
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
            currentProviderName = "Mock (\(kind) unavailable)"
            providerProblem = reason
        }
        panelVM.isMockProvider = health != .healthy
        panelVM.providerName = currentProviderName
    }

    public func openFromMenu() { Task { await present() } }

    /// Menu entry points for screenshots: no selection needed. The panel opens
    /// straight into the region picker.
    public func screenshotFromMenu(ask: Bool) {
        panelVM.present(snapshot: ContextSnapshot(capturedAt: Date()), sourceApp: NSWorkspace.shared.frontmostApplication)
        panelVM.startScreenshot(ask: ask, reopenOnCancel: false)
    }

    // MARK: Settings

    static let panelHotkey = "panel"
    static let screenshotHotkeyID = "screenshot-text"

    /// The active shortcuts (stored, so SwiftUI observes changes).
    public private(set) var hotkey: HotkeyShortcut = .default
    /// "Text from Screenshot" shortcut; nil = off.
    public private(set) var screenshotHotkey: HotkeyShortcut?

    /// Settings value → shortcut: nil = never set (default on), "off" = disabled.
    static func savedScreenshotHotkey(_ saved: String?) -> HotkeyShortcut? {
        switch saved {
        case nil: .screenshotDefault
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

    /// nil turns the screenshot hotkey off. False if the shortcut is taken.
    public func setScreenshotHotkey(_ shortcut: HotkeyShortcut?) -> Bool {
        let hotkeys = container.hotkeys
        let ok = hotkeys.setShortcut(shortcut, for: Self.screenshotHotkeyID)
        if ok { container.settings.screenshotHotkey = shortcut?.id ?? "off" }
        screenshotHotkey = hotkeys.shortcut(for: Self.screenshotHotkeyID)
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
