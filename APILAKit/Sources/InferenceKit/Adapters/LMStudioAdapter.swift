import Core
import Foundation

/// LM Studio speaks the OpenAI-compatible API, so the "adapter" is a thin
/// factory over `OpenAICompatibleProvider` — NO duplicated request/stream logic.
/// It only encodes LM Studio's defaults (local URL, no API key).
public enum LMStudioAdapter {
    public static let defaultBaseURL = URL(string: "http://localhost:1234/v1")!

    public static func make(
        baseURL: URL = defaultBaseURL,
        model: String,
        apiKey: String? = nil,
        supportsVision: Bool = true
    ) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(
            id: "lmstudio",
            configuration: OpenAIConfiguration(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                capabilities: ProviderCapabilities(
                    supportsVision: supportsVision, supportsAudio: false, maxContextTokens: 32_768
                )
            )
        )
    }
}
