import Testing
import Foundation
@testable import Core
@testable import InferenceKit
@testable import ActionKit

@Suite("PromptBuilder, presets, translate")
struct PromptAndPresetTests {
    private let small = ProviderCapabilities(supportsVision: false, supportsAudio: false, maxContextTokens: 10)

    @Test("Long selection is truncated to fit the context window")
    func truncates() {
        let snapshot = ContextSnapshot(selectedText: String(repeating: "a", count: 100), capturedAt: Date())
        let request = PromptBuilder().buildRequest(
            template: PromptTemplate(instruction: "{{selection}}"), snapshot: snapshot, capabilities: small
        )
        #expect(request.parts == [.text(String(repeating: "a", count: 20) + PromptBuilder.truncationMarker)])
    }

    @Test("Short selection is untouched")
    func keepsShort() {
        #expect(PromptBuilder.fit("hello", contextTokens: 10) == "hello")
    }

    @Test("Translate uses the configured languages")
    func translateLanguages() throws {
        let snapshot = ContextSnapshot(selectedText: "Привіт", capturedAt: Date())
        let plan = try TranslateAction(target: "German", fallback: "Polish").plan(for: snapshot)
        let command = try #require(plan.command as? InferenceCommand)
        #expect(command.template.instruction.contains("into German"))
        #expect(command.template.instruction.contains("into Polish"))
        #expect(command.template.system?.contains("same language") == false)
    }

    @Test("Provider kinds carry their defaults")
    func kinds() {
        let router = ProviderKind.openRouter.configuration(apiKey: "k", model: "anthropic/x")
        #expect(router.runtimeID == "anthropic")
        #expect(router.extraHeaders["X-Title"] == "APILA")
        #expect(ProviderKind.lmStudio.configuration(model: "m").baseURL == LMStudioAdapter.defaultBaseURL)
        let custom = URL(string: "http://box:9/v1")!
        #expect(ProviderKind.ollama.configuration(baseURL: custom, model: "m").baseURL == custom)
        #expect(ProviderKind.openAI.needsAPIKey && !ProviderKind.ollama.needsAPIKey)
    }
}
