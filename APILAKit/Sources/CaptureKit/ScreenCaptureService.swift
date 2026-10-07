import Core

/// Region screenshot via ScreenCaptureKit (to be implemented). Currently a stub.
public struct ScreenCaptureService: CaptureService {
    public init() {}

    public func captureRegion() async throws -> ImagePayload {
        // TODO: ScreenCaptureKit region picker + capture.
        throw AppError.notImplemented("ScreenCaptureService.captureRegion")
    }
}
