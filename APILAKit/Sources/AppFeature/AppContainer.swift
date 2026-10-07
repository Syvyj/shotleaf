import Core
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
    private let local = LMStudioAdapter.make(model: "local-model")
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
        await registry.register(local)
        await registry.register(mock)
        await refreshProvider()
    }

    /// Mock Mode: use the local endpoint when it answers, otherwise the mock, so
    /// the UI always works. Called on every panel show, so starting LM Studio
    /// later is picked up without restarting APILA.
    /// ponytail: local-vs-mock only; becomes "user's chosen provider" with provider settings.
    @discardableResult
    public func refreshProvider() async -> String? {
        let healthy = await local.healthCheck() == .healthy
        await registry.setCurrent(id: healthy ? local.id : mock.id)
        return await registry.current()
    }

    public static let mockProviderID = "mock"
}
