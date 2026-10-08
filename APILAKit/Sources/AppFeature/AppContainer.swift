import Core
import Foundation
import InferenceKit
import ContextKit
import PerceptionKit
import ActionKit
import SettingsKit

/// The Composition Root: the ONE place that knows every module and wires
/// concrete implementations to the protocols defined in Core. Holds only the
/// non-UI services (UI-bound, MainActor objects live in AppCoordinator).
public final class AppContainer: Sendable {
    public let events: EventBus
    public let registry: InferenceProviderRegistry
    public let context: ContextAggregator
    public let recognizer: VisionTextRecognizer
    public let hotkeys: GlobalHotkeyService
    public let permissions: PermissionManager
    public let settings: SettingsStore
    public let actionRunner: ActionRunner
    public let clipboard: SystemClipboard
    /// The user's provider. One instance, reconfigured from settings (ADR-0023/0024).
    private let primary = OpenAICompatibleProvider(
        id: "primary",
        configuration: ProviderKind.lmStudio.configuration(model: ProviderKind.lmStudio.defaultModel)
    )
    private let mock = MockStreamingProvider(
        id: AppContainer.mockProviderID,
        reply: "This is a mock response from APILA. Connect LM Studio, Ollama, or an OpenAI-compatible endpoint to get real results."
    )

    public init() {
        let events = EventBus()
        let registry = InferenceProviderRegistry(events: events)
        let clipboard = SystemClipboard()                       // one instance, shared
        let context = ContextAggregator(clipboard: clipboard)
        let recognizer = VisionTextRecognizer()

        self.events = events
        self.registry = registry
        self.context = context
        self.recognizer = recognizer
        self.hotkeys = GlobalHotkeyService()
        self.permissions = PermissionManager(events: events)
        self.settings = SettingsStore()
        self.clipboard = clipboard

        // Executor table: inference is just one of several.
        let executors: [ExecutorID: any ActionExecutor] = [
            .inference: InferenceExecutor(registry: registry, recognizer: recognizer, events: events),
            .clipboard: ClipboardExecutor(service: clipboard),
        ]
        self.actionRunner = ActionRunner(context: context, executors: executors, events: events)
    }

    /// Async wiring that can't happen in a synchronous init (actor calls).
    public func bootstrap() async {
        applyProviderSettings()
        await registry.register(primary)
        await registry.register(mock)
    }

    public var providerKind: ProviderKind {
        ProviderKind(rawValue: settings.providerKind ?? "") ?? .lmStudio
    }

    public var providerModel: String { primary.selectedModel ?? "" }

    /// Pushes saved provider settings (kind, URL, Keychain key, model) into `primary`.
    public func applyProviderSettings() {
        let kind = providerKind
        let config = kind.configuration(
            baseURL: settings.baseURL.flatMap(URL.init(string:)),
            apiKey: settings.apiKey(for: kind.rawValue),
            model: settings.model ?? kind.defaultModel
        )
        primary.reconfigure { $0 = config }
    }

    /// Lists models for not-yet-saved settings (the Settings form's draft).
    public func availableModels(kind: ProviderKind, baseURL: URL?, apiKey: String?) async throws -> [String] {
        let probe = OpenAICompatibleProvider(
            configuration: kind.configuration(baseURL: baseURL, apiKey: apiKey, model: ""),
            session: .shared
        )
        return try await probe.availableModels().map(\.id)
    }

    /// Mock Mode: use the user's provider when it answers, otherwise the mock, so
    /// the UI always works. Called on every panel show, so a server started later
    /// is picked up without restarting APILA.
    public func refreshProvider() async -> ProviderHealth {
        let health = await primary.healthCheck()
        await registry.setCurrent(id: health == .healthy ? primary.id : mock.id)
        return health
    }

    public static let mockProviderID = "mock"
}
