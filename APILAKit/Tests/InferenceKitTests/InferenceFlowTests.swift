import Testing
import Foundation
@testable import Core
@testable import InferenceKit
@testable import ActionKit

private struct StubContext: ContextProviding {
    let text: String
    func snapshot(requirements: ContextRequirements) async throws -> ContextSnapshot {
        ContextSnapshot(selectedText: text, capturedAt: Date())
    }
}
private struct StubRecognizer: TextRecognizing {
    func recognizeText(in image: ImagePayload) async throws -> String { "" }
}
private final class MemoryClipboard: ClipboardService, @unchecked Sendable {
    var stored: String?
    func writeText(_ text: String) async throws { stored = text }
    func readText() async throws -> String? { stored }
}

private func makeRunner(text: String, registry: InferenceProviderRegistry, clipboard: MemoryClipboard, events: EventBus? = nil) -> ActionRunner {
    let executors: [ExecutorID: any ActionExecutor] = [
        .inference: InferenceExecutor(registry: registry, recognizer: StubRecognizer(), events: events),
        .clipboard: ClipboardExecutor(service: clipboard),
    ]
    return ActionRunner(context: StubContext(text: text), executors: executors, events: events)
}

@Suite("Action → Executor flow")
struct InferenceFlowTests {
    @Test("Inference action streams tokens to completion")
    func inferencePath() async throws {
        let registry = InferenceProviderRegistry()
        await registry.register(MockStreamingProvider(reply: "one two three", perTokenDelayMs: 0), makeCurrent: true)
        let runner = makeRunner(text: "fix me", registry: registry, clipboard: MemoryClipboard())

        var full = ""
        var completed = false
        for try await output in runner.run(RewriteAction()) {
            if case .token(let chunk) = output { full += chunk.text }
            if case .completed = output { completed = true }
        }
        #expect(full.contains("one two three"))
        #expect(completed)
    }

    @Test("Non-AI action routes to the clipboard executor")
    func clipboardPath() async throws {
        let registry = InferenceProviderRegistry()
        await registry.register(MockStreamingProvider(perTokenDelayMs: 0), makeCurrent: true)
        let clipboard = MemoryClipboard()
        let runner = makeRunner(text: "copy this", registry: registry, clipboard: clipboard)

        var status: String?
        for try await output in runner.run(CopyAction()) {
            if case .status(let s) = output { status = s }
        }
        #expect(clipboard.stored == "copy this")
        #expect(status != nil)
    }

    @Test("Event bus reports action + provider events")
    func eventBus() async throws {
        let events = EventBus()
        // Subscribing happens synchronously here, so no event can be missed.
        let stream = events.events()
        let collector = Task {
            var received: [AppEvent] = []
            for await event in stream { received.append(event) }
            return received
        }

        let registry = InferenceProviderRegistry(events: events)
        await registry.register(MockStreamingProvider(reply: "hi", perTokenDelayMs: 0), makeCurrent: true)
        let runner = makeRunner(text: "x", registry: registry, clipboard: MemoryClipboard(), events: events)
        for try await _ in runner.run(RewriteAction()) {}

        try await Task.sleep(nanoseconds: 30_000_000)
        collector.cancel()
        let received = await collector.value

        #expect(received.contains(.providerChanged(id: "mock")))
        #expect(received.contains(.actionStarted(id: "rewrite")))
        #expect(received.contains(.actionFinished(id: "rewrite", success: true)))
    }

    @Test("Registry tracks several providers and switches current")
    func multiProvider() async {
        let registry = InferenceProviderRegistry()
        await registry.register(MockStreamingProvider(id: "a"), makeCurrent: true)
        await registry.register(ProviderPreset.openAI(apiKey: "k", model: "gpt-4o-mini"))
        #expect(await registry.registeredIDs().count == 2)
        #expect(await registry.current() == "a")
        await registry.setCurrent(id: "openai")
        #expect(await registry.current() == "openai")
    }
}
