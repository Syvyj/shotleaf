import Testing
import Foundation
@testable import Core
@testable import InferenceKit
@testable import ActionKit
@testable import AppFeature
@testable import PerceptionKit

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

private struct FixedOCR: TextRecognizing {
    func recognizeText(in image: ImagePayload) async throws -> String { "text on screen" }
}

@Suite("Screenshot flow")
@MainActor
struct ScreenshotFlowTests {
    private func makePanel(capture: @escaping () async throws -> ImagePayload) -> PanelViewModel {
        let runner = ActionRunner(
            context: NoContext(),
            executors: [.ocr: OCRExecutor(recognizer: FixedOCR())]
        )
        return PanelViewModel(
            runner: runner,
            inserter: ResultInserter(clipboard: NullClipboard()),
            actions: [],
            accessibilityGranted: { false },
            captureScreen: capture
        )
    }

    @Test("Text from Screenshot: hide → capture → show → OCR text as result")
    func ocr() async throws {
        let vm = makePanel { ImagePayload(data: Data([0]), width: 1, height: 1) }
        var events: [String] = []
        vm.onHide = { events.append("hide") }
        vm.onShow = { events.append("show") }
        vm.present(snapshot: ContextSnapshot(capturedAt: Date()), sourceApp: nil)
        vm.startScreenshot(ask: false)
        try await waitForResult(vm)
        #expect(vm.output == "text on screen")
        #expect(events == ["hide", "show"])
    }

    @Test("Esc in the region picker: from the menu, the panel stays hidden")
    func cancelFromMenu() async throws {
        let vm = makePanel { throw AppError.cancelled }
        var shown = false
        vm.onShow = { shown = true }
        vm.present(snapshot: ContextSnapshot(capturedAt: Date()), sourceApp: nil)
        vm.startScreenshot(ask: false, reopenOnCancel: false)
        try await Task.sleep(for: .milliseconds(50))
        #expect(!shown)
        #expect(vm.screen == .actions)
    }

    @Test("Missing Screen Recording permission is explained")
    func permission() async throws {
        let vm = makePanel { throw AppError.permissionDenied("Screen Recording") }
        vm.present(snapshot: ContextSnapshot(capturedAt: Date()), sourceApp: nil)
        vm.startScreenshot(ask: true)
        try await waitForResult(vm)
        #expect(vm.errorText?.contains("Screen Recording") == true)
    }
}
