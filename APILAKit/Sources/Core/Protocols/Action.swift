import Foundation

/// A user-facing action (Rewrite, Translate, Screenshot, Copy, OCR, Open URL…).
/// An Action is policy: it declares the context it needs and produces a *plan*
/// — which executor should carry it out and with what command. It is NOT tied
/// to AI; inference is just one possible executor.
public protocol Action: Sendable {
    var id: String { get }
    var title: String { get }
    var requirements: ContextRequirements { get }

    func plan(for snapshot: ContextSnapshot) throws -> ActionPlan
}

/// The result of planning an action: a target executor + a command for it.
public struct ActionPlan: Sendable {
    public let executor: ExecutorID
    public let command: any ActionCommand

    public init(executor: ExecutorID, command: any ActionCommand) {
        self.executor = executor
        self.command = command
    }
}

/// Carries out a command. Inference, Capture, OCR, Clipboard, System, Browser,
/// FileSystem and future executors all conform. Concrete executors live in
/// their own modules and are injected by the Composition Root.
public protocol ActionExecutor: Sendable {
    var id: ExecutorID { get }
    func execute(_ command: any ActionCommand, context: ContextSnapshot) -> AsyncThrowingStream<ActionOutput, Error>
}
