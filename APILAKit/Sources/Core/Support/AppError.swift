import Foundation

/// Domain-level errors shared across modules.
public enum AppError: Error, Sendable, Equatable {
    case notImplemented(String)
    case missingContext(String)
    /// The user backed out (e.g. Esc during a screen-region selection).
    case cancelled
    /// A macOS privacy permission is missing (name of the permission).
    case permissionDenied(String)
}
