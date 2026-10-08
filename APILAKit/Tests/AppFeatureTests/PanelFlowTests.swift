import Testing
import Foundation
@testable import Core
@testable import InferenceKit
@testable import ActionKit
@testable import AppFeature

private struct NoContext: ContextProviding {
    func snapshot(requirements: ContextRequirements) async throws -> ContextSnapshot { ContextSnapshot(capturedAt: Date()) }
}
private struct NoOCR: TextRecognizing {
    func recognizeText(in image: ImagePayload) async throws -> String { "" }
}
private struct NullClipboard: ClipboardService {
    func writeText(_ text: String) async throws {}
    func readText() async throws -> String? { nil }
}

@MainActor
private func makePanel() async -> PanelViewModel {
    let registry = InferenceProviderRegistry()
    await registry.register(MockStreamingProvider(reply: "done", perTokenDelayMs: 0), makeCurrent: true)
    let runner = ActionRunner(
        context: NoContext(),
        executors: [.inference: InferenceExecutor(registry: registry, recognizer: NoOCR())]
    )
    return PanelViewModel(
        runner: runner,
        inserter: ResultInserter(clipboard: NullClipboard()),
        actions: [RewriteAction()],
        accessibilityGranted: { false }
    )
}

@MainActor
private func waitForResult(_ vm: PanelViewModel) async throws {
    for _ in 0..<200 where vm.screen != .result { try await Task.sleep(for: .milliseconds(5)) }
    #expect(vm.screen == .result)
}

@Suite("Panel flow")
@MainActor
struct PanelFlowTests {
    @Test("Run → retry → refine → esc back to result, each success recorded")
    func retryAndRefine() async throws {
        let vm = await makePanel()
        var recorded: [String] = []
        vm.onResult = { title, _ in recorded.append(title) }
        vm.present(snapshot: ContextSnapshot(selectedText: "teh text", capturedAt: Date()), sourceApp: nil)

        vm.confirm() // Rewrite
        try await waitForResult(vm)
        #expect(vm.output == "done")

        vm.retry()
        try await waitForResult(vm)

        vm.refine()
        #expect(vm.screen == .customPrompt && vm.isRefining)
        vm.cancel() // esc returns to the result, panel stays open
        #expect(vm.screen == .result && !vm.isRefining)

        vm.refine()
        vm.customPromptText = "shorter"
        vm.confirm()
        try await waitForResult(vm)

        #expect(recorded == ["Rewrite", "Rewrite", "Custom Prompt"])
    }
}
