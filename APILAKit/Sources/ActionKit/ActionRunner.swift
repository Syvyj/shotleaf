import Core

/// Runs an action by: (gathering context) → planning → dispatching to the right
/// executor → streaming its output. Executor-agnostic — inference is just one
/// registered executor among many (clipboard, capture, ocr, …).
public struct ActionRunner: Sendable {
    private let context: any ContextProviding
    private let executors: [ExecutorID: any ActionExecutor]
    private let events: (any EventPublishing)?

    public init(
        context: any ContextProviding,
        executors: [ExecutorID: any ActionExecutor],
        events: (any EventPublishing)? = nil
    ) {
        self.context = context
        self.executors = executors
        self.events = events
    }

    /// Gather context fresh, then run.
    public func run(_ action: any Action) -> AsyncThrowingStream<ActionOutput, Error> {
        stream(action: action) { try await self.context.snapshot(requirements: action.requirements) }
    }

    /// Run against an ALREADY-captured snapshot (e.g. grabbed at hotkey time,
    /// before focus moved to the panel). No re-gathering.
    public func run(_ action: any Action, snapshot: ContextSnapshot) -> AsyncThrowingStream<ActionOutput, Error> {
        stream(action: action) { snapshot }
    }

    private func stream(
        action: any Action,
        snapshot provider: @escaping @Sendable () async throws -> ContextSnapshot
    ) -> AsyncThrowingStream<ActionOutput, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                events?.publish(.actionStarted(id: action.id))
                do {
                    let snapshot = try await provider()
                    let plan = try action.plan(for: snapshot)
                    guard let executor = executors[plan.executor] else {
                        throw AppError.notImplemented("No executor registered for '\(plan.executor)'")
                    }
                    for try await output in executor.execute(plan.command, context: snapshot) {
                        continuation.yield(output)
                    }
                    events?.publish(.actionFinished(id: action.id, success: true))
                    continuation.finish()
                } catch is CancellationError {
                    events?.publish(.actionFinished(id: action.id, success: false))
                    continuation.finish(throwing: InferenceError.cancelled)
                } catch {
                    events?.publish(.actionFinished(id: action.id, success: false))
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
