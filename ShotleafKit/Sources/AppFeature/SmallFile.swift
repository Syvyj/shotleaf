import AppKit
import Core
import ImageIO
import UniformTypeIdentifiers

/// "Save as › JPEG under 1 MB…": the best quality that fits the limit, then
/// smaller pictures when even low quality doesn't. On white (JPEG has no transparency).
enum SmallFile {
    /// What Save as offers, in bytes.
    static let limits = [200_000, 500_000, 1_000_000, 8_000_000, 25_000_000]

    /// Off the main actor: a tall shot takes seconds to shrink.
    nonisolated static func jpeg(_ image: CGImage, under limit: Int) async -> Data? {
        await Task.detached(priority: .userInitiated) { fit(image, under: limit) }.value
    }

    /// Any picture ImageIO reads (PNG, HEIC, TIFF, JPEG).
    static func jpeg(contentsOf url: URL, under limit: Int) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return fit(image, under: limit)
        }.value
    }

    /// Puts the JPEG on the clipboard as a picture and as a file (no PNG/TIFF, so the app that takes it keeps it small).
    @MainActor
    static func copy(_ jpeg: Data) {
        let file = TempFolder.paste.new().appendingPathComponent("Screenshot.jpg")
        try? jpeg.write(to: file)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(jpeg, forType: .init("public.jpeg"))
        pasteboard.setString(file.absoluteString, forType: .fileURL)
        pasteboard.setData(Data(), forType: ClipboardHistory.ownType)
    }

    private nonisolated static func fit(_ image: CGImage, under limit: Int) -> Data? {
        var scale: CGFloat = 1
        for _ in 0..<12 {
            guard let flat = flattened(image, scale: scale) else { return nil }
            if let best = encode(flat, quality: 0.92), best.count <= limit { return best }
            // Binary search for the highest quality that fits.
            var low: CGFloat = 0.35, high: CGFloat = 0.92, found: Data?
            for _ in 0..<6 {
                let q = (low + high) / 2
                if let data = encode(flat, quality: q), data.count <= limit { found = data; low = q } else { high = q }
            }
            if let found { return found }
            scale *= 0.75
        }
        return nil
    }

    /// "1 MB", "500 KB" (the system's own words for sizes).
    static func label(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private nonisolated static func flattened(_ image: CGImage, scale: CGFloat) -> CGImage? {
        let w = max(1, Int((CGFloat(image.width) * scale).rounded())), h = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let ctx = CGContext.sRGB(width: w, height: h, alpha: .noneSkipLast)
        else { return nil }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    private nonisolated static func encode(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
