import Core
import CoreImage
import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

/// APILA's built-in model (ADR-0006): Gemma 4 E2B, 4-bit, sees images — run
/// on this Mac with MLX. Downloaded once from Hugging Face when the user asks
/// (Settings), loaded on first use and kept in memory.
/// ponytail: stays loaded until quit (~2 GB); unload after idle if memory matters.
public actor EmbeddedModel {
    public static let shared = EmbeddedModel()
    public static let configuration = VLMRegistry.gemma4_E2B_it_4bit
    public static let displayName = "Gemma 4 E2B"

    private var container: ModelContainer?
    private var loading: Task<ModelContainer, Error>?

    /// Where Hugging Face keeps this model (`~/.cache/huggingface/hub/models--…`).
    public nonisolated static var directory: URL? {
        guard case .id(let id, _) = configuration.id, let repo = Repo.ID(rawValue: id) else { return nil }
        return HubCache.default.repoDirectory(repo: repo, kind: .model)
    }

    /// Weights are on disk (a finished download).
    public nonisolated static var isDownloaded: Bool {
        guard let directory, let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        else { return false }
        return files.contains { ($0 as? URL)?.pathExtension == "safetensors" }
    }

    /// Bytes on disk.
    public nonisolated static var sizeOnDisk: Int64 {
        guard let directory, let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
        else { return 0 }
        return files.reduce(Int64(0)) { sum, item in
            let size = (item as? URL).flatMap { try? $0.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize }
            return sum + Int64(size ?? 0)
        }
    }

    /// Downloads the model if needed, then loads it. `progress` gets 0…1
    /// while downloading.
    public func load(progress: @Sendable @escaping (Double) -> Void = { _ in }) async throws -> ModelContainer {
        if let container { return container }
        if let loading { return try await loading.value }
        let task = Task {
            try await loadModelContainer(
                from: #hubDownloader(), using: #huggingFaceTokenizerLoader(),
                configuration: Self.configuration
            ) { progress($0.fractionCompleted) }
        }
        loading = task
        defer { loading = nil }
        let loaded = try await task.value
        container = loaded
        return loaded
    }

    /// Frees memory and disk.
    public func delete() throws {
        container = nil
        if let directory = Self.directory, FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}

/// The built-in model as an `InferenceProvider`, next to the API providers.
public struct EmbeddedProvider: InferenceProvider {
    public static let providerID = "embedded"
    public let id = EmbeddedProvider.providerID

    public init() {}

    public var capabilities: ProviderCapabilities {
        ProviderCapabilities(supportsVision: true, supportsAudio: false, maxContextTokens: 32_768)
    }

    public var selectedModel: String? { EmbeddedModel.displayName }

    public func availableModels() async throws -> [ModelInfo] {
        [ModelInfo(id: EmbeddedModel.displayName, displayName: EmbeddedModel.displayName)]
    }

    public func healthCheck() async -> ProviderHealth {
        EmbeddedModel.isDownloaded ? .healthy : .unhealthy(reason: "the built-in model isn't downloaded yet (Settings → Download)")
    }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<TokenChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let container = try await EmbeddedModel.shared.load()
                    var parameters = GenerateParameters()
                    if let t = request.options?.temperature { parameters.temperature = Float(t) }
                    if let n = request.options?.maxTokens { parameters.maxTokens = n }
                    let session = ChatSession(container, instructions: request.system, generateParameters: parameters)
                    let text = request.parts.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined(separator: "\n\n")
                    let images = request.parts.compactMap { part -> UserInput.Image? in
                        guard case .image(let payload) = part, let image = CIImage(data: payload.data) else { return nil }
                        return .ciImage(image)
                    }
                    for try await chunk in session.streamResponse(to: text, images: images) {
                        continuation.yield(TokenChunk(text: chunk))
                    }
                    continuation.yield(TokenChunk(text: "", finishReason: "stop"))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
