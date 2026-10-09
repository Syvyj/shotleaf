import Core
import AppKit
import ApplicationServices
import CoreGraphics
import IOKit.hid

/// Real macOS permission checks. Platform APIs live here in the app layer; the
/// rest of the system uses Core's `PermissionService`. NOTE: these return
/// meaningful values only from a signed `.app` bundle — TCC is identity-bound.
public final class PermissionManager: PermissionService, @unchecked Sendable {
    public init() {}

    public func status(_ kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .denied
        case .inputMonitoring:
            switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
            case kIOHIDAccessTypeGranted: return .granted
            case kIOHIDAccessTypeDenied: return .denied
            default: return .notDetermined
            }
        }
    }

    public func request(_ kind: PermissionKind) async {
        switch kind {
        case .accessibility:
            // Literal avoids referencing the non-Sendable global
            // `kAXTrustedCheckOptionPrompt` (its value is stable).
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        case .inputMonitoring:
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }

    public func openSystemSettings(for kind: PermissionKind) {
        let anchor: String
        switch kind {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
