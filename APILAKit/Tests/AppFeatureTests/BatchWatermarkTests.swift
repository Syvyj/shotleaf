import Testing
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
@testable import AppFeature

@Suite("Watermark photos")
@MainActor
struct BatchWatermarkTests {
    /// A 400×200 JPEG stored sideways (EXIF orientation 6) with a capture date.
    static func sidewaysJPEG(in dir: URL) throws -> URL {
        let ctx = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        let url = dir.appendingPathComponent("photo.jpg")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:11 12:00:00"],
        ] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    @Test("Same pixels count, upright, metadata kept, original untouched")
    func render() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("apila-batch-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let photo = try Self.sidewaysJPEG(in: dir)
        let before = try Data(contentsOf: photo)

        let out = try BatchWatermark.render(photo, mark: Watermark(text: "APILA", position: 4, size: 0.5, opacity: 1),
                                            format: .original, into: dir) // same folder: must not overwrite
        #expect(out.lastPathComponent == "photo watermarked.jpg")
        #expect(try Data(contentsOf: photo) == before)
        let source = try #require(CGImageSourceCreateWithURL(out as CFURL, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 200 && props[kCGImagePropertyPixelHeight] as? Int == 400)
        #expect((props[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:10:11 12:00:00")
    }

    @Test("A photo moved by hand keeps its spot; the rest follow the common one; renders")
    func overrides() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("apila-batch-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let photo = try Self.sidewaysJPEG(in: dir)
        let model = BatchWatermark()
        model.watermark = Watermark(text: "© Studio", position: 8, size: 0.4, opacity: 0.8)
        model.add([photo, dir.appendingPathComponent("notes.txt")])
        #expect(model.photos == [photo] && model.selected == photo)
        model.overrides[photo] = .init(position: 8, center: CGPoint(x: 0.3, y: 0.2))
        #expect(model.mark(for: photo).center == CGPoint(x: 0.3, y: 0.2))
        #expect(model.folder?.lastPathComponent == "Watermarked")
        let sidebarNeeds = NSHostingView(rootView: BatchWatermarkView(model: model)).fittingSize.height
        #expect(sidebarNeeds <= 700, "needs \(sidebarNeeds) pt") // fits the window without scrolling
        try renderPreview(BatchWatermarkView(model: model).frame(width: 1000, height: 700), "batch-watermark.png")
    }
}
