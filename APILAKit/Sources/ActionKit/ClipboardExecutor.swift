import Core

/// A non-AI executor: writes text to the clipboard via an injected
/// `ClipboardService`. Demonstrates that the executor abstraction is not tied
/// to inference. Lives in ActionKit because it depends only on Core.
public struct ClipboardExecutor: ActionExecutor {
    public let id = ExecutorID.clipboard
    private let service: any ClipboardService

    public init(service: any ClipboardService) {
        self.service = service
    }

    public func execute(_ command: any ActionCommand, context: ContextSnapshot) -> AsyncThrowingStream<ActionOutput, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let cmd = command as? ClipboardWriteCommand else {
                        throw AppError.notImplemented("ClipboardExecutor received \(type(of: command))")
                    }
                    try await service.writeText(cmd.text)
                    continuation.yield(.status("Copied \(cmd.text.count) characters"))
                    continuation.yield(.completed)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
