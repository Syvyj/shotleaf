import AppKit
import ImageIO
import UniformTypeIdentifiers

/// "Watermark photos": one watermark for many photos, with a different spot
/// (a grid spot, or dragged by hand) on any photo that needs it. The photos
/// keep their pixels, size, colour profile and metadata; only the mark is added.
@MainActor
@Observable
final class BatchWatermark {
    enum Format: String, CaseIterable, Identifiable {
        case original, png, jpeg
        var id: String { rawValue }
    }

    /// Where one photo's mark goes, when it isn't where the others' go.
    struct Placement: Equatable {
        var position: Int
        var center: CGPoint?
    }

    var photos: [URL] = []
    var selected: URL?
    var watermark = Watermark.saved ?? Watermark()
    var overrides: [URL: Placement] = [:]
    var format: Format = .original
    /// nil = a "Watermarked" folder next to the first photo.
    var outputFolder: URL?
    /// 0…1 while applying.
    private(set) var progress: Double?
    private(set) var result: String?

    static let imageTypes: [UTType] = [.jpeg, .png, .heic, .tiff, .webP, .bmp, .gif]

    func add(_ urls: [URL]) {
        let images = urls.filter { url in
            UTType(filenameExtension: url.pathExtension).map { type in Self.imageTypes.contains { type.conforms(to: $0) } } ?? false
        }
        photos += images.filter { !photos.contains($0) }
        if selected == nil { selected = photos.first }
        result = nil
    }

    func remove(_ url: URL) {
        photos.removeAll { $0 == url }
        overrides[url] = nil
        if selected == url { selected = photos.first }
    }

    /// The watermark as it goes on `url`.
    func mark(for url: URL) -> Watermark {
        var w = watermark
        if let o = overrides[url] { w.position = o.position; w.center = o.center }
        return w
    }

    var folder: URL? {
        outputFolder ?? photos.first.map { $0.deletingLastPathComponent().appendingPathComponent("Watermarked", isDirectory: true) }
    }

    func apply() async {
        guard let folder, progress == nil else { return }
        Watermark.saved = watermark
        progress = 0
        var failed = 0
        let jobs = photos.map { ($0, mark(for: $0)) }
        let format = format
        for (i, (url, mark)) in jobs.enumerated() {
            let ok = await Task.detached { (try? Self.render(url, mark: mark, format: format, into: folder)) != nil }.value
            if !ok { failed += 1 }
            progress = Double(i + 1) / Double(jobs.count)
        }
        progress = nil
        result = failed == 0
            ? String(localized: "Done: \(jobs.count) photos in “\(folder.lastPathComponent)”")
            : String(localized: "Done with \(failed) errors — those photos couldn’t be read or written")
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    // MARK: Rendering (off the main thread)

    enum Failure: Error { case unreadable, unwritable }

    /// The photo upright (EXIF orientation applied) at full size.
    nonisolated static func upright(_ url: URL) -> (image: CGImage, source: CGImageSource)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: max(w, h),
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary)
        else { return nil }
        return (image, source)
    }

    /// Writes the photo with its mark into `folder` under the same name; returns the new file.
    @discardableResult
    nonisolated static func render(_ url: URL, mark: Watermark, format: Format, into folder: URL) throws -> URL {
        guard let (image, source) = upright(url) else { throw Failure.unreadable }
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Failure.unwritable }
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.draw(image, in: full)
        // The watermark draws y-down.
        ctx.translateBy(x: 0, y: full.height)
        ctx.scaleBy(x: 1, y: -1)
        mark.draw(in: ctx, area: full)
        guard let marked = ctx.makeImage() else { throw Failure.unwritable }

        let sourceType = CGImageSourceGetType(source).map { $0 as String } ?? UTType.png.identifier
        let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        let type: String = switch format {
        case .png: UTType.png.identifier
        case .jpeg: UTType.jpeg.identifier
        case .original: writable.contains(sourceType) ? sourceType : UTType.png.identifier
        }
        let ext = type == sourceType ? url.pathExtension : UTType(type)?.preferredFilenameExtension ?? "png" // keep .jpg as .jpg
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var out = folder.appendingPathComponent(url.deletingPathExtension().lastPathComponent).appendingPathExtension(ext)
        if out.standardizedFileURL == url.standardizedFileURL { // never over the original
            out = folder.appendingPathComponent(url.deletingPathExtension().lastPathComponent + " watermarked").appendingPathExtension(ext)
        }
        guard let destination = CGImageDestinationCreateWithURL(out as CFURL, type as CFString, 1, nil) else { throw Failure.unwritable }
        // Keep the metadata (camera, date, GPS, profile); the pixels are upright now.
        var props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        props[kCGImagePropertyOrientation] = 1
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            props[kCGImagePropertyTIFFDictionary] = tiff
        }
        props[kCGImageDestinationLossyCompressionQuality] = 1.0 // best quality for JPEG/HEIC
        CGImageDestinationAddImage(destination, marked, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unwritable }
        return out
    }
}
