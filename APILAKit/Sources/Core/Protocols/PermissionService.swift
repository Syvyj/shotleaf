import Foundation

/// macOS privacy permissions APILA needs. Granting them requires a signed
/// `.app` bundle (TCC binds to bundle identity).
public enum PermissionKind: String, Sendable, CaseIterable, Hashable {
    case accessibility
    case screenRecording
    case inputMonitoring
}

public enum PermissionStatus: Sendable, Equatable {
    case granted
    case denied
    case notDetermined
}

/// Checks/requests system permissions. Concrete implementation lives in the app
/// layer (uses ApplicationServices / CoreGraphics / IOKit); the rest of the
/// system depends only on this protocol.
public protocol PermissionService: Sendable {
    func status(_ kind: PermissionKind) -> PermissionStatus
    func request(_ kind: PermissionKind) async
    func openSystemSettings(for kind: PermissionKind)
}
