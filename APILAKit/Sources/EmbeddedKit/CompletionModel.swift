import Core
import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// The built-in completion model, run on this Mac with MLX (ADR-0065).
/// Downloaded once from Hugging Face when the user asks (Settings), loaded on
/// first use and kept in memory.
/// ponytail: stays loaded until quit (~2 GB); unload after idle if memory matters.
public actor EmbeddedModel {
    /// Gemma 4 E2B *base*: a plain text continuer for inline completion —
    /// instruct models answer instead of continuing, and need a slow prompt.
    public static let completion = EmbeddedModel(
        configuration: ModelConfiguration(id: "mlx-community/gemma-4-e2b-4bit"), displayName: "Gemma 4 E2B base")

    public nonisolated let configuration: ModelConfiguration
    public nonisolated let displayName: String

    private var container: ModelContainer?
    private var loading: Task<ModelContainer, Error>?
    /// What the model already read for the last completion (see `complete`).
    private let promptCache = PromptCache()

    init(configuration: ModelConfiguration, displayName: String) {
        self.configuration = configuration
        self.displayName = displayName
    }

    /// Where Hugging Face keeps this model (`~/.cache/huggingface/hub/models--…`).
    public nonisolated var directory: URL? {
        guard case .id(let id, _) = configuration.id, let repo = Repo.ID(rawValue: id) else { return nil }
        return HubCache.default.repoDirectory(repo: repo, kind: .model)
    }

    /// Weights are on disk (a finished download).
    public nonisolated var isDownloaded: Bool {
        guard let directory, let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        else { return false }
        return files.contains { ($0 as? URL)?.pathExtension == "safetensors" }
    }

    /// Bytes on disk.
    public nonisolated var sizeOnDisk: Int64 {
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
        let configuration = configuration
        let task = Task {
            // Only the language part (no vision/audio towers) — less memory.
            try await LLMModelFactory.shared.loadContainer(
                from: #hubDownloader(), using: #huggingFaceTokenizerLoader(), configuration: configuration
            ) { progress($0.fractionCompleted) }
        }
        loading = task
        defer { loading = nil }
        let loaded = try await task.value
        container = loaded
        return loaded
    }

    /// The continuation stops at a token the model is less sure of than this:
    /// pure noise. Good first words often score 5–10% (the eval run showed
    /// " на"@0.10 → "надіюся", " a"@0.07 → "a look"), so it stays low.
    public static let minTokenProbability: Float = 0.03

    /// How `prefix` goes on, from a base model: greedy, short, one line, and
    /// cut where the model starts guessing (see `minConfidence`). `onPartial`
    /// gets the confident text so far after every token, to show as it's
    /// written. `finished` — the model ended the line itself (not cut).
    /// Prompt tokens the last completion didn't have to read again.
    public var lastReusedTokens: Int { promptCache.reused }

    /// `minProbability` / `trace` are for the evaluation run: see every token
    /// and how sure the model was of it.
    public func complete(
        _ prefix: String, maxTokens: Int = 10, minProbability: Float = EmbeddedModel.minTokenProbability,
        trace: (@Sendable (String, Float) -> Void)? = nil,
        onPartial: @Sendable @escaping (String) -> Void = { _ in }
    ) async throws -> (text: String, finished: Bool) {
        let container = try await load()
        let promptCache = promptCache
        return try await container.perform { context in
            let tokens = context.tokenizer.encode(text: prefix, addSpecialTokens: true)
            var parameters = GenerateParameters()
            parameters.temperature = 0
            parameters.repetitionPenalty = ProcessInfo.processInfo.environment["APILA_NO_PENALTY"] == nil ? 1.15 : nil
            // Between key presses the text barely changes: keep what the model
            // already read and feed it only the new tokens.
            let (cache, reused) = try promptCache.prepare(for: tokens, model: context.model, parameters: parameters)
            let input = LMInput(tokens: MLXArray(Array(tokens[reused...])))
            let probe = ConfidenceProbe()
            let iterator = try TokenIterator(
                input: input, model: context.model, cache: cache, parameters: parameters,
                components: GenerationComponents(logitProcessorFactory: { probe })
            )
            promptCache.reused = reused
            var kept: [Int] = []
            var finished = true
            _ = generate(input: input, context: context, iterator: iterator) { ids in
                if Task.isCancelled { finished = false; return .stop }
                let p = probe.box.last ?? 1
                trace?(context.tokenizer.decode(tokenIds: [ids.last ?? 0], skipSpecialTokens: false), p)
                if p < minProbability || ids.count > maxTokens { finished = false; return .stop }
                kept = ids
                let text = context.tokenizer.decode(tokenIds: ids, skipSpecialTokens: true)
                onPartial(text)
                // A suggestion never goes past the line or the sentence: no need to write on.
                return text.contains(where: { "\n.!?…".contains($0) }) ? .stop : .more
            }
            return (context.tokenizer.decode(tokenIds: kept, skipSpecialTokens: true), finished)
        }
    }

    /// Frees memory and disk.
    public func delete() throws {
        container = nil
        if let directory, FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}

/// The model's memory of the last prompt (its KV cache), reused by the next
/// completion when the new prompt starts the same way — the usual case while
/// typing. Rewound to the shared start; rebuilt when it can't be rewound
/// exactly (past the sliding window) or nothing is shared.
/// Used only inside `ModelContainer.perform`, which runs one at a time.
private final class PromptCache: @unchecked Sendable {
    private var cache: [KVCache]?
    private var tokens: [Int] = []
    /// Tokens skipped last time (for the eval run).
    var reused = 0

    func prepare(for tokens: [Int], model: any LanguageModel, parameters: GenerateParameters) throws -> ([KVCache], Int) {
        defer { self.tokens = tokens }
        let enabled = ProcessInfo.processInfo.environment["APILA_NO_PROMPT_CACHE"] == nil // eval: compare against no reuse
        if enabled, let cache, canTrimPromptCache(cache), let offset = cache.first?.offset {
            let shared = zip(self.tokens, tokens).prefix { $0 == $1 }.count
            let keep = min(shared, tokens.count - 1) // the model must read at least one token
            // Only worth it — and only checked — for a real shared start (typing on);
            // rewinding to almost nothing gave different answers in the eval.
            if keep >= max(16, tokens.count / 2), offset >= keep {
                trimPromptCache(cache, numTokens: offset - keep)
                if cache.allSatisfy({ $0.offset == keep }) { return (cache, keep) }
            }
        }
        let fresh = try model.newCache(parameters: parameters)
        cache = fresh
        return (fresh, 0)
    }
}

/// Watches the logits and notes how likely the chosen (greedy = top) token
/// was. Changes nothing.
private struct ConfidenceProbe: LogitProcessor {
    final class Box: @unchecked Sendable { var last: Float? } // one generation, one thread
    let box = Box()

    mutating func prompt(_ prompt: MLXArray) {}

    func process(logits: MLXArray) -> MLXArray {
        box.last = softmax(logits.asType(.float32), axis: -1).max().item(Float.self)
        return logits
    }

    mutating func didSample(token: MLXArray) {}
}

