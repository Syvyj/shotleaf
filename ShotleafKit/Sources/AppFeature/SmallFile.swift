import AppKit
import Core
import ImageIO
import Core
import UniformTypeIdentifiers

/// "Save as › JPEG under 1 MB…": the best quality that fits the limit, then
/// smaller pictures when even low quality doesn't. On white (JPEG has no transparency).
enum SmallFile {
    /// What Save as offers, in bytes.
    static let limits = [1_000_000, 500_000, 200_000]

    static func jpeg(_ image: CGImage, under limit: Int) -> Data? {
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

    private static func flattened(_ image: CGImage, scale: CGFloat) -> CGImage? {
        let w = max(1, Int((CGFloat(image.width) * scale).rounded())), h = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let ctx = CGContext.sRGB(width: w, height: h, alpha: .noneSkipLast)
        else { return nil }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    private static func encode(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
