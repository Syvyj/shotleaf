import Foundation

/// A single inference backend (embedded MLX, LM Studio, Ollama, OpenAI-compatible,
/// OpenRouter…). Streams a response for an already-built request, can list its
/// models, and can report health. Model *selection* is a provider-internal
/// concern (config), so it is not on this protocol.
public protocol InferenceProvider: Sendable {
    var id: String { get }
    var capabilities: ProviderCapabilities { get }
    /// The currently selected model id, if any (Provider → Runtime → Model).
    var selectedModel: String? { get }

    /// Models this provider can serve. May hit the network.
    func availableModels() async throws -> [ModelInfo]

    /// Lightweight reachability/readiness probe. Never throws — returns a status.
    func healthCheck() async -> ProviderHealth

    /// Stream tokens for a request. Cancelling the consuming task cancels the
    /// underlying work.
    func stream(_ request: AIRequest) -> AsyncThrowingStream<TokenChunk, Error>
}

/// Resolves which provider to use among possibly many active providers.
/// Concrete registry lives in InferenceKit; ActionKit depends only on this.
public protocol InferenceProviderResolving: Sendable {
    func currentProvider() async -> (any InferenceProvider)?
    func provider(id: String) async -> (any InferenceProvider)?
}

/// Builds a `ContextSnapshot` limited to the requested pieces.
public protocol ContextProviding: Sendable {
    func snapshot(requirements: ContextRequirements) async throws -> ContextSnapshot
}

/// Captures a region of the screen as an image.
public protocol CaptureService: Sendable {
    func captureRegion() async throws -> ImagePayload
    /// A long screenshot of an area the user scrolls.
    func captureScrolling() async throws -> ImagePayload
}

extension CaptureService {
    public func captureScrolling() async throws -> ImagePayload { throw AppError.cancelled }
}

/// Recognizes text in an image (Vision). Part of the broader PerceptionKit.
public protocol TextRecognizing: Sendable {
    func recognizeText(in image: ImagePayload) async throws -> String
}

/// A fired global hotkey.
public struct HotkeyEvent: Sendable, Equatable {
    public let identifier: String
    public init(identifier: String) {
        self.identifier = identifier
    }
}

/// Registers global hotkeys and emits events.
public protocol HotkeyService: Sendable {
    var events: AsyncStream<HotkeyEvent> { get }
    /// False if the shortcut couldn't be registered (e.g. owned by another app).
    @discardableResult func start() -> Bool
    func stop()
}
