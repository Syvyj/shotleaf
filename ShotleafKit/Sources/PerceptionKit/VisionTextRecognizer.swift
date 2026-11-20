import Core
import Foundation
import Vision

/// On-device OCR via the Vision framework — nothing leaves the Mac. Language is
/// auto-detected (Latin, Cyrillic incl. Ukrainian, CJK…). A QR code or barcode in the picture
/// comes first, as what it holds (often a link).
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
            let codes = VNDetectBarcodesRequest()
            try VNImageRequestHandler(data: data).perform([request, codes])
            let held = (codes.results ?? []).compactMap(\.payloadStringValue)
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return (NSOrderedSet(array: held).array as! [String] + lines).joined(separator: "\n")
        }.value
    }
}
