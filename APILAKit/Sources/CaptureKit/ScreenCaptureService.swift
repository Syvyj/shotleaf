import Core
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Region screenshot with APILA's own picker (`RegionPicker`): frozen screen,
/// loupe, window pick, full screen, repeat last region. Esc → `AppError.cancelled`.
public struct ScreenCaptureService: CaptureService {
    public init() {}

    public func captureRegion() async throws -> ImagePayload {
        // Without Screen Recording permission macOS returns only the wallpaper.
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw AppError.permissionDenied("Screen Recording")
        }
        let image = try await RegionPicker.shared.pick()
        return try Self.payload(png: Self.png(image))
    }

    static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw AppError.missingContext("Can't encode screenshot")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw AppError.missingContext("Can't encode screenshot") }
        return data as Data
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
