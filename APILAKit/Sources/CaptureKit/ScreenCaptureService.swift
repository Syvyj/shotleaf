import Core
import CoreGraphics
import Foundation
import ImageIO

/// Region screenshot: the user drags a region (or Space → picks a window), Esc
/// cancels. Uses the system `screencapture -i` — the exact ⌘⇧4 UI users know.
/// ponytail: system picker instead of a custom ScreenCaptureKit overlay; build our
/// own overlay only when we need in-picker extras (magnifier, annotations).
public struct ScreenCaptureService: CaptureService {
    public init() {}

    public func captureRegion() async throws -> ImagePayload {
        // Without Screen Recording permission macOS returns only the wallpaper.
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw AppError.permissionDenied("Screen Recording")
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("apila-capture-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", url.path] // interactive, no shutter sound
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }

        // Esc → screencapture exits without writing a file.
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { throw AppError.cancelled }
        return try Self.payload(png: data)
    }

    static func payload(png data: Data) throws -> ImagePayload {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { throw AppError.missingContext("Unreadable screenshot") }
        return ImagePayload(data: data, width: width, height: height, mimeType: "image/png")
    }
}
