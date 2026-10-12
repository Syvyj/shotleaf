import Core
import Foundation
import CaptureKit
import PerceptionKit
import SettingsKit

/// The Composition Root: the ONE place that knows every module and wires
/// concrete implementations to the protocols defined in Core. Holds only the
/// non-UI services (UI-bound, MainActor objects live in AppCoordinator).
public final class AppContainer: Sendable {
    public let capture = ScreenCaptureService()
    public let recognizer = VisionTextRecognizer()
    public let hotkeys = GlobalHotkeyService()
    public let permissions = PermissionManager()
    public let settings = SettingsStore()

    public init() {}
}
