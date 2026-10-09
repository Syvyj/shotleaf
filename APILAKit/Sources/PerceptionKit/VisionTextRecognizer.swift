import Core
import Foundation
import Vision

/// On-device OCR via the Vision framework — nothing leaves the Mac. Language is
/// auto-detected (Latin, Cyrillic incl. Ukrainian, CJK…).
public struct VisionTextRecognizer: TextRecognizing {
    public init() {}

    public func recognizeText(in image: ImagePayload) async throws -> String {
        let data = image.data
        // Vision is synchronous and CPU-heavy: keep it off the caller's actor.
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(data: data).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }
}
