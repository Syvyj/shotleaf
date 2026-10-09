import Foundation

/// Captures a region of the screen as an image.
public protocol CaptureService: Sendable {
    func captureRegion() async throws -> ImagePayload
    /// A long screenshot of an area the user scrolls.
    func captureScrolling() async throws -> ImagePayload
}

extension CaptureService {
    public func captureScrolling() async throws -> ImagePayload { throw AppError.cancelled }
}

/// Recognizes text in an image (Vision). Part of the broader PerceptionKit.
public protocol TextRecognizing: Sendable {
    func recognizeText(in image: ImagePayload) async throws -> String
}

/// A fired global hotkey.
public struct HotkeyEvent: Sendable, Equatable {
    public let identifier: String
    public init(identifier: String) {
        self.identifier = identifier
    }
}

/// Registers global hotkeys and emits events.
public protocol HotkeyService: Sendable {
    var events: AsyncStream<HotkeyEvent> { get }
    /// False if the shortcut couldn't be registered (e.g. owned by another app).
    @discardableResult func start() -> Bool
    func stop()
}
