import Core
import InferenceKit
import ActionKit
import Foundation

// A runnable, network-free proof of the architecture:
//   Action → Executor → (Inference | Clipboard | …) → ActionOutput stream
//   + Provider/Runtime/Model separation + Event Bus
// Run with:  swift run inference-demo

struct DemoContext: ContextProviding {
    let text: String
    func snapshot(requirements: ContextRequirements) async throws -> ContextSnapshot {
        ContextSnapshot(selectedText: text, capturedAt: Date())
    }
}
struct DemoRecognizer: TextRecognizing {
    func recognizeText(in image: ImagePayload) async throws -> String { "" }
}
/// In-memory clipboard so the non-AI executor runs without AppKit.
final class MemoryClipboard: ClipboardService, @unchecked Sendable {
    private var stored: String?
    func writeText(_ text: String) async throws { stored = text }
    func readText() async throws -> String? { stored }
}

func out(_ s: String) { FileHandle.standardOutput.write(Data(s.utf8)) }

@main
struct InferenceDemo {
    static func main() async {
        let events = EventBus()

        // Subscribe to the Event Bus and print everything it emits.
        let logger = Task {
            for await event in events.events() {
                print("  · event: \(event)")
            }
        }

        let registry = InferenceProviderRegistry(events: events)

        // Several providers active at once — same code path, different config.
        await registry.register(
            MockStreamingProvider(reply: "AI is now just one executor among many."),
            makeCurrent: true
        )
        await registry.register(ProviderPreset.lmStudio(model: "gemma-4-e2b"))
        await registry.register(ProviderPreset.openRouter(apiKey: "or-demo", model: "anthropic/claude-3.5-sonnet"))

        print("Registered providers : \(await registry.registeredIDs())")
        print("Current provider     : \(await registry.current() ?? "-")")

        // Provider → Runtime → Model is now explicit (see OpenRouter runtime).
        if let p = await registry.provider(id: "openrouter") {
            let models = (try? await p.availableModels()) ?? []
            print("OpenRouter selected  : provider=\(p.id) model=\(p.selectedModel ?? "-")")
            print("  (models call returns \(models.count) from live endpoint; offline here)")
        }

        // Executors: inference + a non-AI clipboard executor.
        let executors: [ExecutorID: any ActionExecutor] = [
            .inference: InferenceExecutor(registry: registry, recognizer: DemoRecognizer(), events: events),
            .clipboard: ClipboardExecutor(service: MemoryClipboard()),
        ]
        let runner = ActionRunner(
            context: DemoContext(text: "i has bad grammar and need fixing pls"),
            executors: executors,
            events: events
        )

        // 1) AI action through the inference executor.
        print("\n=== Rewrite (executor: inference) ===")
        await drive(runner.run(RewriteAction()))

        // 2) Non-AI action through the clipboard executor — same runner, same API.
        print("\n=== Copy (executor: clipboard) ===")
        await drive(runner.run(CopyAction()))

        // 3) Switch active provider — emits providerChanged on the bus.
        await registry.setCurrent(id: "lmstudio")
        print("\nSwitched current → \(await registry.current() ?? "-")")

        // let trailing events flush, then stop the logger
        try? await Task.sleep(nanoseconds: 50_000_000)
        logger.cancel()
    }

    static func drive(_ stream: AsyncThrowingStream<ActionOutput, Error>) async {
        do {
            for try await output in stream {
                switch output {
                case .token(let chunk): out(chunk.text)
                case .text(let text): out(text)
                case .status(let status): print("\n  [status] \(status)")
                case .image: print("\n  [image]")
                case .url(let url): print("\n  [url] \(url)")
                case .completed: print("\n  [completed]")
                }
            }
        } catch {
            print("\n  [error] \(error)")
        }
    }
}
