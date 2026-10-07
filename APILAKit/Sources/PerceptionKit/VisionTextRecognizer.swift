import Core

/// On-device OCR via the Vision framework (to be implemented). PerceptionKit
/// will also host object detection, barcode recognition, and image analysis.
/// Currently a stub.
public struct VisionTextRecognizer: TextRecognizing {
    public init() {}

    public func recognizeText(in image: ImagePayload) async throws -> String {
        // TODO: VNRecognizeTextRequest on the decoded image.
        throw AppError.notImplemented("VisionTextRecognizer.recognizeText")
    }
}
