import AppKit

/// "Combine Images…": several pictures as one, in rows, on white with a gap.
/// The layout is picked for them: rows of the same height, every row as wide
/// as the others, with as many per row as makes the result closest to 16:10.
enum Collage {
    /// Between pictures, in pixels.
    static let gap: CGFloat = 24
    static let aim: CGFloat = 16 / 10

    /// Where each picture goes (pixels, y down) and the whole size, `columns` per row.
    static func layout(_ sizes: [CGSize], columns: Int) -> (frames: [CGRect], size: CGSize) {
        guard !sizes.isEmpty else { return ([], .zero) }
        let rows = stride(from: 0, to: sizes.count, by: max(columns, 1)).map { Array($0..<min($0 + columns, sizes.count)) }
        // In its row, each picture at the row's lowest height (nothing grows)…
        let heights = rows.map { row in row.map { sizes[$0].height }.min()! }
        let natural = zip(rows, heights).map { row, h in row.reduce(0) { $0 + sizes[$1].width * h / sizes[$1].height } }
        // …then every row scaled to the narrowest one.
        let width = zip(rows, natural).map { row, w in w + gap * CGFloat(row.count - 1) }.min()!
        var frames = [CGRect](repeating: .zero, count: sizes.count)
        var y: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let scale = (width - gap * CGFloat(row.count - 1)) / natural[i]
            let h = (heights[i] * scale).rounded()
            var x: CGFloat = 0
            for j in row {
                let w = (sizes[j].width * heights[i] / sizes[j].height * scale).rounded()
                frames[j] = CGRect(x: x, y: y, width: w, height: h)
                x += w + gap
            }
            y += h + gap
        }
        return (frames, CGSize(width: width.rounded(), height: y - gap))
    }

    /// How many per row: the result's shape closest to 16:10.
    static func columns(for sizes: [CGSize]) -> Int {
        (1...max(sizes.count, 1)).min { a, b in
            func off(_ c: Int) -> CGFloat {
                let size = layout(sizes, columns: c).size
                return abs(log(size.width / max(size.height, 1) / aim))
            }
            return off(a) < off(b)
        }!
    }

    static func make(_ images: [CGImage]) -> CGImage? {
        let sizes = images.map { CGSize(width: $0.width, height: $0.height) }
        let (frames, size) = layout(sizes, columns: columns(for: sizes))
        guard size.width >= 1, size.height >= 1,
              let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.interpolationQuality = .high
        for (image, frame) in zip(images, frames) { // CG's y goes up
            ctx.draw(image, in: CGRect(x: frame.minX, y: size.height - frame.maxY, width: frame.width, height: frame.height))
        }
        return ctx.makeImage()
    }
}
