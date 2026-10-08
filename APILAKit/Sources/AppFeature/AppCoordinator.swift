import Core
import ActionKit
import InferenceKit
import AppKit
import Observation
import SwiftUI

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

    public init(container: AppContainer = AppContainer()) {
        self.container = container
        let inserter = ResultInserter(clipboard: container.clipboard)
        let permissions = container.permissions
        self.panelVM = PanelViewModel(
            runner: container.actionRunner,
            inserter: inserter,
            actions: [],
            accessibilityGranted: { permissions.status(.accessibility) == .granted }
        )
        applyTranslateSettings()
    }

    public func start() async {
        await container.bootstrap()
        await refreshProvider()
        refreshPermissions()

        let panel = FloatingPanelController { [weak self] in
            if let self { return AnyView(PanelView(vm: self.panelVM)) }
            return AnyView(EmptyView())
        }
        self.panel = panel
        panelVM.onClose = { [weak self] in self?.panel?.hide() }

        hotkeyRegistered = container.hotkeys.setShortcut(.with(id: container.settings.hotkey))
        hotkey = container.hotkeys.shortcut
        hotkeyTask = Task { [weak self] in
            guard let self else { return }
            for await _ in self.container.hotkeys.events {
                await self.present()
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
    }

    public func openFromMenu() { Task { await present() } }

    // MARK: Settings

    /// The active shortcut (stored, so SwiftUI observes changes).
    public private(set) var hotkey: HotkeyShortcut = .default

    /// Returns false (and keeps the old one) if the shortcut is taken.
    public func setHotkey(id: String) -> Bool {
        let ok = container.hotkeys.setShortcut(.with(id: id))
        if ok { container.settings.hotkey = id }
        hotkeyRegistered = ok || hotkeyRegistered
        hotkey = container.hotkeys.shortcut
        return ok
    }

    public struct ProviderSettings: Equatable {
        public var kind: ProviderKind
        public var baseURL: String
        public var apiKey: String
        public var model: String
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
            model: (isSaved ? settings.model : nil) ?? kind.defaultModel
        )
    }

    public func saveProvider(_ draft: ProviderSettings) async {
        let settings = container.settings
        settings.providerKind = draft.kind.rawValue
        let url = draft.baseURL.trimmingCharacters(in: .whitespaces)
        settings.baseURL = url.isEmpty || url == draft.kind.defaultBaseURL.absoluteString ? nil : url
        settings.model = draft.model.trimmingCharacters(in: .whitespaces)
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

    // MARK: Permissions (for Settings)

    public func refreshPermissions() {
        for kind in PermissionKind.allCases {
            permissions[kind] = container.permissions.status(kind)
        }
    }

    public func request(_ kind: PermissionKind) async {
        await container.permissions.request(kind)
        refreshPermissions()
    }

    public func openSettings(for kind: PermissionKind) {
        container.permissions.openSystemSettings(for: kind)
    }
}
