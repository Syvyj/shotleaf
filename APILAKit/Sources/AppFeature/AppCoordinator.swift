import Core
import ActionKit
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
    public private(set) var currentProviderName: String = "—"

    public init(container: AppContainer = AppContainer()) {
        self.container = container
        let inserter = ResultInserter(clipboard: container.clipboard)
        let permissions = container.permissions
        self.panelVM = PanelViewModel(
            runner: container.actionRunner,
            inserter: inserter,
            actions: BuiltInActions.inferenceActions(),
            accessibilityGranted: { permissions.status(.accessibility) == .granted }
        )
    }

    /// False when the global shortcut couldn't be registered (e.g. taken by another app).
    public private(set) var hotkeyRegistered = true

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

        hotkeyRegistered = container.hotkeys.start()
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

    private func refreshProvider() async {
        let id = await container.refreshProvider()
        currentProviderName = id ?? "—"
        panelVM.isMockProvider = id == AppContainer.mockProviderID
    }

    public func openFromMenu() { Task { await present() } }

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
