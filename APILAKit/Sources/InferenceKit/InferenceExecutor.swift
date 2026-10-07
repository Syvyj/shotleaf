import Core

/// The AI executor — one `ActionExecutor` among many. Resolves the current
/// provider, applies capabilities (vision vs. OCR fallback), builds the request
/// via PromptBuilder, streams tokens as `ActionOutput.token`, and emits
/// inference events.
public struct InferenceExecutor: ActionExecutor {
    public let id = ExecutorID.inference

    private let registry: any InferenceProviderResolving
    private let recognizer: any TextRecognizing
    private let events: (any EventPublishing)?
    private let builder = PromptBuilder()

    public init(
        registry: any InferenceProviderResolving,
        recognizer: any TextRecognizing,
        events: (any EventPublishing)? = nil
    ) {
        self.registry = registry
        self.recognizer = recognizer
        self.events = events
    }

    public func execute(_ command: any ActionCommand, context: ContextSnapshot) -> AsyncThrowingStream<ActionOutput, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let cmd = command as? InferenceCommand else {
                        throw AppError.notImplemented("InferenceExecutor received \(type(of: command))")
                    }
                    guard let provider = await registry.currentProvider() else {
                        throw AppError.providerUnavailable
                    }

                    // OCR fallback only when the action wants screen text and the
                    // provider can't see images.
                    var snapshot = context
                    if cmd.includeScreenText,
                       snapshot.recognizedScreenText == nil,
                       !provider.capabilities.supportsVision,
                       let image = snapshot.screenImage {
                        let text = try await recognizer.recognizeText(in: image)
                        events?.publish(.ocrFinished(characters: text.count))
                        snapshot = snapshot.withRecognizedScreenText(text)
                    }

                    let request = builder.buildRequest(
                        template: cmd.template,
                        snapshot: snapshot,
                        capabilities: provider.capabilities,
                        options: cmd.options
                    )

                    let model = provider.selectedModel ?? ""
                    events?.publish(.inferenceStarted(provider: provider.id, model: model))
                    for try await chunk in provider.stream(request) {
                        continuation.yield(.token(chunk))
                    }
                    events?.publish(.inferenceFinished(provider: provider.id, model: model))
                    continuation.yield(.completed)
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
