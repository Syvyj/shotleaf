import Foundation

/// Domain-level errors shared across modules.
public enum AppError: Error, Sendable, Equatable {
    case notImplemented(String)
    case missingContext(String)
    case providerUnavailable
}
