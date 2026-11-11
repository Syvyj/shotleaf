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
/// first use and let go after `idleTime` without a request (the next one loads it again).
public actor EmbeddedModel {
    /// Gemma 4 E2B *base*: a plain text continuer for inline completion —
    /// instruct models answer instead of continuing, and need a slow prompt.
    /// Pinned to one commit: a change upstream can't swap the weights under users.
    public static let completion = EmbeddedModel(
        configuration: ModelConfiguration(
            id: "mlx-community/gemma-4-e2b-4bit", revision: "a280baf4aece348bd0f561ca43b9d47cc66d8498"),
        displayName: "Gemma 4 E2B base")

    public nonisolated let configuration: ModelConfiguration
    public nonisolated let displayName: String

    private var container: ModelContainer?
    private var loading: Task<ModelContainer, Error>?
    private var generating = false
    /// What the model already read for the last completion (see `complete`).
    private let promptCache = PromptCache()
    /// The most MLX keeps in its buffer cache, over the model itself.
    public static let cacheLimit = 256 * 1_048_576
    /// Unused this long, the model leaves memory (it holds ~2 GB).
    public static let idleTime: Duration = .seconds(600)
    private var idleUnload: Task<Void, Never>?

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
        // MLX keeps freed buffers for reuse, by default up to the GPU's whole working set (~11 GB on a
        // 16 GB Mac): prompts of every length while typing filled it until the Mac froze (0.2.1).
        Memory.cacheLimit = Self.cacheLimit
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
        scheduleUnload()
        // One at a time: the cache below is shared, and the actor lets the next call in while this one
        // waits on the model. A newer key press has cancelled this call if it's still waiting.
        while generating {
            if Task.isCancelled { return ("", false) }
            try? await Task.sleep(for: .milliseconds(5))
        }
        generating = true
        defer { generating = false }
        let promptCache = promptCache
        return try await container.perform { context in
            let tokens = context.tokenizer.encode(text: prefix, addSpecialTokens: true)
            var parameters = GenerateParameters()
            parameters.temperature = 0
            parameters.repetitionPenalty = ProcessInfo.processInfo.environment["SHOTLEAF_NO_PENALTY"] == nil ? 1.15 : nil
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
            let (stream, task) = generateTokenTask(promptTokenCount: input.text.tokens.size, modelConfiguration: context.configuration,
                                                   tokenizer: context.tokenizer, iterator: iterator)
            var ids: [Int] = [], kept: [Int] = []
            var finished = true
            for await event in stream {
                guard case .token(let id) = event else { continue }
                if Task.isCancelled { finished = false; break }
                ids.append(id)
                // As tuned (minProbability): a token stays only if the model is sure of the one after it, which the
                // generation has already worked out by now. The last one has no next: its own counts.
                // ponytail: the thresholds were set against this "next token" reading; judging each token by its
                // own confidence shows one word more in 4 of 21 eval samples. Retune both together if changed.
                let p = probe.box.probability(ids.count) ?? probe.box.probability(ids.count - 1) ?? 1
                trace?(context.tokenizer.decode(tokenIds: [id], skipSpecialTokens: false), p)
                if p < minProbability || ids.count > maxTokens { finished = false; break }
                kept = ids
                let text = context.tokenizer.decode(tokenIds: ids, skipSpecialTokens: true)
                onPartial(text)
                // A suggestion never goes past the line or the sentence: no need to write on.
                if text.contains(where: { "\n.!?…".contains($0) }) { break }
            }
            // Stopped early: the generation must be done with the shared cache before the next one starts.
            task.cancel()
            await task.value
            return (context.tokenizer.decode(tokenIds: kept, skipSpecialTokens: true), finished)
        }
    }

    private func scheduleUnload() {
        idleUnload?.cancel()
        idleUnload = Task {
            try? await Task.sleep(for: Self.idleTime)
            guard !Task.isCancelled else { return }
            unload()
        }
    }

    /// Out of memory (a running completion keeps its own reference until it's done).
    /// What MLX holds now, in bytes: in use, kept in its buffer cache, and the most it has held.
    public nonisolated static var memory: (active: Int, cache: Int, peak: Int) {
        (Memory.activeMemory, Memory.cacheMemory, Memory.peakMemory)
    }

    public func unload() {
        idleUnload?.cancel()
        container = nil
        promptCache.reset()
        Memory.clearCache()
    }

    /// Stops a download in progress (what's on disk stays for the next try).
    public func cancel() {
        loading?.cancel()
        loading = nil
    }

    /// Frees memory and disk.
    public func delete() throws {
        unload()
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

    func reset() {
        cache = nil
        tokens = []
    }

    func prepare(for tokens: [Int], model: any LanguageModel, parameters: GenerateParameters) throws -> ([KVCache], Int) {
        defer { self.tokens = tokens }
        let enabled = ProcessInfo.processInfo.environment["SHOTLEAF_NO_PROMPT_CACHE"] == nil // eval: compare against no reuse
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
    /// Written by the generation, read by the loop that takes its tokens.
    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [Float] = []
        func add(_ p: Float) { lock.withLock { all.append(p) } }
        /// The confidence of the token at `index` (0 = the first generated).
        func probability(_ index: Int) -> Float? { lock.withLock { index < all.count ? all[index] : nil } }
    }
    let box = Box()

    mutating func prompt(_ prompt: MLXArray) {}

    func process(logits: MLXArray) -> MLXArray {
        box.add(softmax(logits.asType(.float32), axis: -1).max().item(Float.self))
        return logits
    }

    mutating func didSample(token: MLXArray) {}
}

