import Foundation
import Synchronization

/// Internal events. NOT analytics/logging — the backbone for future Debug,
/// Plugins, Automation, Macros and Statistics. `.custom` keeps it open for
/// plugin-defined events without editing this enum.
public enum AppEvent: Sendable, Equatable {
    case hotkeyPressed(id: String)
    case actionStarted(id: String)
    case actionFinished(id: String, success: Bool)
    case inferenceStarted(provider: String, model: String)
    case inferenceFinished(provider: String, model: String)
    case screenshotTaken
    case ocrFinished(characters: Int)
    case providerChanged(id: String)
    case permissionGranted(name: String)
    case custom(name: String)
}

/// Publishes events to all subscribers.
public protocol EventPublishing: Sendable {
    func publish(_ event: AppEvent)
}

/// Subscribes to the event stream.
public protocol EventSubscribing: Sendable {
    func events() -> AsyncStream<AppEvent>
}

/// A simple in-process fan-out event bus. Multiple subscribers each get their
/// own stream; publishing delivers to all current subscribers.
public final class EventBus: EventPublishing, EventSubscribing, Sendable {
    private let subscribers = Mutex<[UUID: AsyncStream<AppEvent>.Continuation]>([:])

    public init() {}

    public func publish(_ event: AppEvent) {
        let continuations = subscribers.withLock { Array($0.values) }
        for continuation in continuations {
            continuation.yield(event)
        }
    }

    public func events() -> AsyncStream<AppEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            self.subscribers.withLock { $0[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.subscribers.withLock { $0[id] = nil }
            }
        }
    }
}
