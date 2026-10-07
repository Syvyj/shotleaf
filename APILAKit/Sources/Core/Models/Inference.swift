import Foundation

/// What a provider can do. The Action/PromptBuilder layer reads this to decide
/// whether to attach an image directly (vision) or fall back to OCR text.
public struct ProviderCapabilities: Sendable, Equatable {
    public let supportsVision: Bool
    public let supportsAudio: Bool
    public let maxContextTokens: Int

    public init(supportsVision: Bool, supportsAudio: Bool, maxContextTokens: Int) {
        self.supportsVision = supportsVision
        self.supportsAudio = supportsAudio
        self.maxContextTokens = maxContextTokens
    }
}

/// Per-request generation tuning. Optional so actions opt in only when needed.
public struct GenerationOptions: Sendable, Equatable {
    public var temperature: Double?
    public var maxTokens: Int?

    public init(temperature: Double? = nil, maxTokens: Int? = nil) {
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

/// A fully-formed, provider-agnostic request. The provider does NOT know what
/// "Rewrite" or "Translate" means — that knowledge lives in ActionKit. The
/// *model* is a provider-config concern, not part of the request.
public struct AIRequest: Sendable, Equatable {
    public let system: String?
    public let parts: [ContentPart]
    /// Optional hint to route to a specific provider; nil = use current.
    public let preferredProviderID: String?
    public let options: GenerationOptions?

    public init(
        system: String? = nil,
        parts: [ContentPart],
        preferredProviderID: String? = nil,
        options: GenerationOptions? = nil
    ) {
        self.system = system
        self.parts = parts
        self.preferredProviderID = preferredProviderID
        self.options = options
    }
}

/// One streamed token (delta). `finishReason` is non-nil on the terminating
/// chunk (e.g. "stop", "length").
public struct TokenChunk: Sendable, Equatable {
    public let text: String
    public let finishReason: String?

    public init(text: String, finishReason: String? = nil) {
        self.text = text
        self.finishReason = finishReason
    }
}

/// The engine that actually runs a model inside a provider. Separating this
/// from Provider and Model matters: LM Studio (provider) can run MLX OR
/// llama.cpp (runtime); OpenRouter (provider) routes to Anthropic/OpenAI
/// (runtime); Embedded (provider) uses MLX (runtime).
public struct RuntimeInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

/// A model exposed by a provider, optionally tagged with the runtime serving it.
public struct ModelInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String?
    public let runtime: RuntimeInfo?
    public let ownedBy: String?

    public init(id: String, displayName: String? = nil, runtime: RuntimeInfo? = nil, ownedBy: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.runtime = runtime
        self.ownedBy = ownedBy
    }
}

/// Fully-qualified identity of "what generates tokens": Provider → Runtime → Model.
public struct ModelRef: Sendable, Hashable {
    public let providerID: String
    public let runtimeID: String?
    public let modelID: String

    public init(providerID: String, runtimeID: String? = nil, modelID: String) {
        self.providerID = providerID
        self.runtimeID = runtimeID
        self.modelID = modelID
    }
}

/// Result of a provider health check.
public enum ProviderHealth: Sendable, Equatable {
    case healthy
    case unhealthy(reason: String)
}

/// Errors surfaced by inference providers. Network/HTTP/API failures are mapped
/// into these so callers (and the UI) get a stable, typed contract.
public enum InferenceError: Error, Sendable, Equatable {
    case invalidURL
    case noModelSelected
    case network(String)
    case timedOut
    case cancelled
    case http(status: Int, body: String?)
    case api(message: String, type: String?, code: String?)
    case decoding(String)
    case unhealthy(String)
}
