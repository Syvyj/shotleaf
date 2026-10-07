import Core
import Foundation

/// Ready-made configurations of the ONE `OpenAICompatibleProvider`. Each vendor
/// differs only in base URL / auth / headers / capabilities — never in logic.
/// This is what makes several providers active at once trivial.
public enum ProviderPreset {
    public static func openAI(apiKey: String, model: String, organization: String? = nil) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(
            id: "openai",
            configuration: OpenAIConfiguration(
                baseURL: URL(string: "https://api.openai.com/v1")!,
                apiKey: apiKey,
                model: model,
                organization: organization,
                capabilities: ProviderCapabilities(supportsVision: true, supportsAudio: false, maxContextTokens: 128_000)
            )
        )
    }

    public static func openRouter(apiKey: String, model: String, appName: String = "APILA") -> OpenAICompatibleProvider {
        // OpenRouter model ids embed the upstream runtime, e.g. "anthropic/claude-3.5-sonnet".
        let runtime = model.contains("/") ? String(model.split(separator: "/")[0]) : nil
        return OpenAICompatibleProvider(
            id: "openrouter",
            configuration: OpenAIConfiguration(
                baseURL: URL(string: "https://openrouter.ai/api/v1")!,
                apiKey: apiKey,
                model: model,
                runtimeID: runtime,
                extraHeaders: ["HTTP-Referer": "https://apila.app", "X-Title": appName],
                capabilities: ProviderCapabilities(supportsVision: true, supportsAudio: false, maxContextTokens: 128_000)
            )
        )
    }

    public static func ollama(baseURL: URL = URL(string: "http://localhost:11434/v1")!, model: String) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(
            id: "ollama",
            configuration: OpenAIConfiguration(
                baseURL: baseURL,
                apiKey: nil,
                model: model,
                capabilities: ProviderCapabilities(supportsVision: false, supportsAudio: false, maxContextTokens: 32_768)
            )
        )
    }

    public static func lmStudio(baseURL: URL = LMStudioAdapter.defaultBaseURL, model: String) -> OpenAICompatibleProvider {
        LMStudioAdapter.make(baseURL: baseURL, model: model)
    }
}
