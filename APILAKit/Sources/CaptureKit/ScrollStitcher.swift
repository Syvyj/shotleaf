import CoreGraphics
import Foundation

/// Glues frames of a scrolling area into one tall image (unit-tested).
///
/// Each frame is compared with the previous one row by row (each row boiled
/// down to a few brightness blocks, edges left out so an overlay scrollbar
/// doesn't spoil the match). The shift where the rows differ least is how far
/// the content scrolled; the rows that scrolled in at the bottom are appended.
/// Rows that stay put at the top and bottom while the rest moves are a sticky
/// header / footer: left out of the matching, the footer kept once at the end.
/// ponytail: down-scrolling only.
struct ScrollStitcher {
    let width: Int
    let height: Int
    /// The stitched picture so far, RGBA rows top to bottom.
    private(set) var pixels: [UInt8] = []
    private var previous: [Row] = []
    /// Sticky bars, in rows; decided on the first real scroll (nil = not yet).
    private var header = 0
    private var footer: Int?
    /// The sticky footer from the latest frame, drawn once below the content.
    private var footerPixels: [UInt8] = []
    /// Height limit of the result, in pixels (memory guard).
    let maxHeight: Int

    /// A row's brightness in a few blocks across: survives the sub-pixel
    /// blur of smooth scrolling (Chromium, Electron), unlike an exact hash.
    struct Row: Equatable {
        let blocks: [Float]
        /// One color across the row: matches anything, so it doesn't count.
        let plain: Bool
    }

    static let blockCount = 16

    enum Step: Equatable {
        case first
        case added(rows: Int)
        case still          // nothing moved
        case lost           // scrolled further than one frame: no overlap
        case full           // reached maxHeight
    }

    init(width: Int, height: Int, maxHeight: Int = 24_000) {
        self.width = width
        self.height = height
        self.maxHeight = maxHeight
    }

    var stitchedHeight: Int { (pixels.count + footerPixels.count) / (width * 4) }

    /// Adds one frame (RGBA8, `width`×`height`, tightly packed).
    mutating func add(_ frame: [UInt8]) -> Step {
        precondition(frame.count == width * height * 4)
        let rows = Self.rows(frame, width: width, height: height)
        defer { previous = rows }
        guard !previous.isEmpty else {
            pixels = frame
            return .first
        }
        let rowBytes = width * 4
        let edges = footer.map { (top: header, bottom: $0) } ?? Self.staticEdges(previous, rows)
        if footer == nil, edges.top + edges.bottom >= height - Self.minOverlap(height) { return .still }
        guard let shift = Self.shift(from: previous, to: rows, skipTop: edges.top, skipBottom: edges.bottom) else { return .lost }
        guard shift > 0 else { return .still }
        if footer == nil { // the first real scroll: what stayed put is a bar
            header = edges.top
            let bar = rows.suffix(edges.bottom)
            let bottom = bar.filter { !$0.plain }.count * 2 >= bar.count ? edges.bottom : 0 // mostly content, not a blank margin
            footer = bottom
            pixels.removeLast(bottom * rowBytes) // the first frame's footer goes to the end instead
        }
        let f = footer ?? 0
        footerPixels = Array(frame[(height - f) * rowBytes ..< height * rowBytes])
        let room = maxHeight - stitchedHeight
        guard room > 0 else { return .full }
        let take = min(shift, room)
        pixels.append(contentsOf: frame[(height - f - shift) * rowBytes ..< (height - f - shift + take) * rowBytes])
        return take < shift ? .full : .added(rows: take)
    }

    func image() -> CGImage? {
        guard !pixels.isEmpty else { return nil }
        let h = stitchedHeight
        return (pixels + footerPixels).withUnsafeBytes { buffer -> CGImage? in
            guard let provider = CGDataProvider(data: Data(buffer) as CFData) else { return nil }
            return CGImage(width: width, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }

    // MARK: Matching

    static func rows(_ frame: [UInt8], width: Int, height: Int) -> [Row] {
        // Middle 80% of the row, every other pixel: skips scrollbars and
        // window edges, and keeps up with frames coming in several a second.
        let from = width / 10, to = width - width / 10
        let span = max(1, (to - from) / blockCount)
        return frame.withUnsafeBytes { raw in
            let px = raw.bindMemory(to: UInt8.self)
            return (0..<height).map { y in
                var blocks = [Float](repeating: 0, count: blockCount)
                for b in 0..<blockCount {
                    var sum = 0, n = 0
                    for x in stride(from: from + b * span, to: min(from + (b + 1) * span, to), by: 2) {
                        let i = (y * width + x) * 4
                        sum += Int(px[i]) * 3 + Int(px[i + 1]) * 6 + Int(px[i + 2]) // ~luma ×10
                        n += 1
                    }
                    blocks[b] = n > 0 ? Float(sum) / Float(n * 10) : 0
                }
                let plain = (blocks.max() ?? 0) - (blocks.min() ?? 0) < 0.5
                return Row(blocks: blocks, plain: plain)
            }
        }
    }

    /// How many rows the content moved up between `a` and `b`: 0 = still,
    /// nil = no convincing overlap. The shift where the rows differ least
    /// wins — if it clearly beats the typical shift (smooth scrolling blurs
    /// rows a little, so nothing matches exactly).
    static func minOverlap(_ h: Int) -> Int { max(8, h / 8) }

    static func distance(_ x: Row, _ y: Row) -> Float {
        var d: Float = 0
        for i in 0..<blockCount { d += abs(x.blocks[i] - y.blocks[i]) }
        return d
    }

    /// Rows that didn't change at the top and bottom (each at most a third of the frame).
    static func staticEdges(_ a: [Row], _ b: [Row]) -> (top: Int, bottom: Int) {
        let h = min(a.count, b.count)
        let same = { (k: Int) in distance(a[k], b[k]) < 8 }
        let top = (0..<h).first { !same($0) } ?? h
        let bottom = (0..<h).first { !same(h - 1 - $0) } ?? h
        guard top < h else { return (h, 0) } // nothing changed at all
        return (min(top, h / 3), min(bottom, h / 3))
    }

    /// Rows `skipTop` / `skipBottom` (sticky bars) are left out of the matching.
    static func shift(from a: [Row], to b: [Row], skipTop: Int = 0, skipBottom: Int = 0) -> Int? {
        let h = min(a.count, b.count)
        let minOverlap = minOverlap(h)
        let span = h - skipTop - skipBottom
        guard span > minOverlap else { return 0 }
        var best: (shift: Int, distance: Float)?
        var all: [Float] = []
        for s in 0...(span - minOverlap) {
            var total: Float = 0, counted = 0
            for k in skipTop..<(h - skipBottom - s) where !b[k].plain {
                let d = distance(b[k], a[k + s])
                total += d
                counted += 1
                // Early out once clearly worse than the best (the rough figure is enough for the median).
                if let best, counted.isMultiple(of: 64), total / Float(counted) > best.distance * 3 + 1 { break }
            }
            guard counted >= 4 else { continue }
            let distance = total / Float(counted)
            all.append(distance)
            if distance < (best?.distance ?? .infinity) - 0.0001 { best = (s, distance) }
        }
        guard let best, !all.isEmpty else { return 0 } // nothing but blank rows: nothing to tell

        let typical = all.sorted()[all.count / 2]
        return best.distance <= typical * 0.5 || best.distance < 0.5 ? best.shift : nil
    }
}
