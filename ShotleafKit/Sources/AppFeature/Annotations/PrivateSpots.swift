import AppKit
import Vision

/// "Blur private info": faces, emails, phone numbers, card numbers and
/// secret-looking tokens on a screenshot, found on this Mac with Vision.
enum PrivateSpots {
    /// The areas to blur, in image points (origin top-left, y down) of a picture `size` big.
    static func find(in image: CGImage, size: CGSize) async -> [CGRect] {
        let normalized: [CGRect] = await Task.detached(priority: .userInitiated) {
            let faces = VNDetectFaceRectanglesRequest()
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .accurate
            text.usesLanguageCorrection = false // addresses and numbers, not words
            try? VNImageRequestHandler(cgImage: image).perform([faces, text])
            let found = (text.results ?? []).flatMap { line -> [CGRect] in
                guard let candidate = line.topCandidates(1).first else { return [] }
                return ranges(in: candidate.string).compactMap { try? candidate.boundingBox(for: $0)?.boundingBox }
            }
            return (faces.results ?? []).map(\.boundingBox) + found
        }.value
        // Vision's rects are 0…1 with the origin bottom-left.
        return normalized.map { r in
            CGRect(x: r.minX * size.width, y: (1 - r.maxY) * size.height, width: r.width * size.width, height: r.height * size.height)
                .insetBy(dx: -3, dy: -3)
        }
    }

    /// The private parts of one line of text.
    nonisolated static func ranges(in line: String) -> [Range<String.Index>] {
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber]
        let detected = ((try? NSDataDetector(types: types.rawValue))?.matches(in: line, range: NSRange(line.startIndex..., in: line)) ?? [])
            .filter { $0.resultType == .phoneNumber || $0.url?.scheme == "mailto" }
            .compactMap { Range($0.range, in: line) }
        // Card numbers ("4242 4242 4242 4242") and tokens, as the clipboard sees them.
        let secrets = line.matches(of: /[0-9][0-9 \-]{11,22}[0-9]|[^\s]{20,}/)
            .filter { ClipboardHistory.looksSensitive(String($0.output)) }
            .map(\.range)
        return detected + secrets
    }
}
