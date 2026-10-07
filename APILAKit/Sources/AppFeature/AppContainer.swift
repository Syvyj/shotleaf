import Core
import InferenceKit
import ContextKit
import CaptureKit
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
    public let capture: ScreenCaptureService
    public let hotkeys: GlobalHotkeyService
    public let permissions: PermissionManager
    public let settings: SettingsStore
    public let actionRunner: ActionRunner
    public let clipboard: SystemClipboard

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
        self.capture = ScreenCaptureService()
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
    /// Mock Mode: register the local provider AND a mock; pick the mock if the
    /// local endpoint isn't reachable, so the UI always works.
    public func bootstrap() async {
        let local = LMStudioAdapter.make(model: "local-model")
        let mock = MockStreamingProvider(
            reply: "This is a mock response from APILA. Connect LM Studio, Ollama, or an OpenAI-compatible endpoint to get real results."
        )
        await registry.register(local)
        await registry.register(mock)

        if case .healthy = await local.healthCheck() {
            await registry.setCurrent(id: local.id)
        } else {
            await registry.setCurrent(id: mock.id)
        }
    }
}
