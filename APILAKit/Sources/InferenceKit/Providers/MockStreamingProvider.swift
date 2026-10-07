import Core
import Foundation

/// An in-process provider that streams a canned reply token by token. Lets us
/// exercise the full Action → stream → completion path (and cancellation)
/// without any network or server. Used by tests and the `inference-demo`.
public final class MockStreamingProvider: InferenceProvider {
    public let id: String
    public let capabilities: ProviderCapabilities
    private let tokens: [String]
    private let perTokenDelayMs: UInt64

    public var selectedModel: String? { "mock-model" }

    public init(
        id: String = "mock",
        reply: String = "Hello from the APILA mock provider.",
        perTokenDelayMs: UInt64 = 15,
        capabilities: ProviderCapabilities = ProviderCapabilities(
            supportsVision: false, supportsAudio: false, maxContextTokens: 8_192
        )
    ) {
        self.id = id
        self.capabilities = capabilities
        self.tokens = reply.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        self.perTokenDelayMs = perTokenDelayMs
    }

    public func availableModels() async throws -> [ModelInfo] {
        [ModelInfo(id: "mock-model", ownedBy: "apila")]
    }

    public func healthCheck() async -> ProviderHealth { .healthy }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<TokenChunk, Error> {
        let tokens = self.tokens
        let delay = self.perTokenDelayMs
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for (index, token) in tokens.enumerated() {
                        try Task.checkCancellation()
                        if delay > 0 { try await Task.sleep(nanoseconds: delay * 1_000_000) }
                        continuation.yield(TokenChunk(text: index == 0 ? token : " " + token))
                    }
                    continuation.yield(TokenChunk(text: "", finishReason: "stop"))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: InferenceError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
