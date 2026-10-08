import Core
import Foundation
import Vision

/// On-device OCR via the Vision framework — nothing leaves the Mac. Language is
/// auto-detected (Latin, Cyrillic incl. Ukrainian, CJK…). PerceptionKit will
/// later also host barcode / object detection.
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

/// Executor for `OCRCommand`: recognizes text in the image and yields it.
public struct OCRExecutor: ActionExecutor {
    public let id = ExecutorID.ocr
    private let recognizer: any TextRecognizing
    private let events: (any EventPublishing)?

    public init(recognizer: any TextRecognizing, events: (any EventPublishing)? = nil) {
        self.recognizer = recognizer
        self.events = events
    }

    public func execute(_ command: any ActionCommand, context: ContextSnapshot) -> AsyncThrowingStream<ActionOutput, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let cmd = command as? OCRCommand else {
                        throw AppError.notImplemented("OCRExecutor received \(type(of: command))")
                    }
                    let text = try await recognizer.recognizeText(in: cmd.image)
                    events?.publish(.ocrFinished(characters: text.count))
                    guard !text.isEmpty else { throw AppError.missingContext("No text found in the screenshot") }
                    continuation.yield(.text(text))
                    continuation.yield(.completed)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
