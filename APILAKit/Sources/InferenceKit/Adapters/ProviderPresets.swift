import Core
import Foundation

/// The vendors APILA knows how to talk to. All of them speak the OpenAI-compatible
/// API, so a kind is only defaults (URL / auth / headers / capabilities) for the
/// ONE `OpenAICompatibleProvider` — never different logic.
public enum ProviderKind: String, CaseIterable, Sendable, Identifiable {
    /// The built-in model (EmbeddedKit) — no URL, key or server.
    case embedded
    case lmStudio, ollama, openAI, openRouter, custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .embedded: String(localized: "Built-in (Gemma 4 E2B, on this Mac)")
        case .lmStudio: "LM Studio"
        case .ollama: "Ollama"
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        case .custom: String(localized: "Custom (OpenAI-compatible)")
        }
    }

    public var defaultBaseURL: URL {
        switch self {
        case .embedded: URL(string: "apila://embedded")!
        case .lmStudio: LMStudioAdapter.defaultBaseURL
        case .ollama: URL(string: "http://localhost:11434/v1")!
        case .openAI: URL(string: "https://api.openai.com/v1")!
        case .openRouter: URL(string: "https://openrouter.ai/api/v1")!
        case .custom: URL(string: "http://localhost:8080/v1")!
        }
    }

    public var needsAPIKey: Bool { self == .openAI || self == .openRouter }

    /// LM Studio serves whatever model is loaded, whatever id we send.
    public var defaultModel: String { self == .lmStudio ? "local-model" : "" }

    public var capabilities: ProviderCapabilities {
        switch self {
        case .openAI, .openRouter: ProviderCapabilities(supportsVision: true, supportsAudio: false, maxContextTokens: 128_000)
        case .embedded: ProviderCapabilities(supportsVision: true, supportsAudio: false, maxContextTokens: 32_768)
        case .lmStudio: ProviderCapabilities(supportsVision: true, supportsAudio: false, maxContextTokens: 32_768)
        case .ollama, .custom: ProviderCapabilities(supportsVision: false, supportsAudio: false, maxContextTokens: 32_768)
        }
    }

    public func configuration(baseURL: URL? = nil, apiKey: String? = nil, model: String) -> OpenAIConfiguration {
        var config = OpenAIConfiguration(
            baseURL: baseURL ?? defaultBaseURL,
            apiKey: apiKey,
            model: model,
            capabilities: capabilities
        )
        if self == .openRouter {
            // OpenRouter model ids embed the upstream runtime, e.g. "anthropic/<model>".
            config.runtimeID = model.contains("/") ? String(model.split(separator: "/")[0]) : nil
            config.extraHeaders = ["HTTP-Referer": "https://apila.app", "X-Title": "APILA"]
        }
        return config
    }
}

/// Ready-made providers, one per kind.
public enum ProviderPreset {
    public static func openAI(apiKey: String, model: String, organization: String? = nil) -> OpenAICompatibleProvider {
        var config = ProviderKind.openAI.configuration(apiKey: apiKey, model: model)
        config.organization = organization
        return OpenAICompatibleProvider(id: "openai", configuration: config)
    }

    public static func openRouter(apiKey: String, model: String) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(id: "openrouter", configuration: ProviderKind.openRouter.configuration(apiKey: apiKey, model: model))
    }

    public static func ollama(baseURL: URL? = nil, model: String) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(id: "ollama", configuration: ProviderKind.ollama.configuration(baseURL: baseURL, model: model))
    }

    public static func lmStudio(baseURL: URL = LMStudioAdapter.defaultBaseURL, model: String) -> OpenAICompatibleProvider {
        LMStudioAdapter.make(baseURL: baseURL, model: model)
    }
}
