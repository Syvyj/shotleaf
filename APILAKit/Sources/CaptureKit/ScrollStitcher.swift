import CoreGraphics
import Foundation

/// Glues frames of a scrolling area into one tall image (unit-tested).
///
/// Each frame is compared with the previous one row by row (each row boiled
/// down to a few brightness blocks, edges left out so an overlay scrollbar
/// doesn't spoil the match). The shift where the rows differ least is how far
/// the content scrolled; the rows that scrolled in at the bottom are appended.
/// ponytail: down-scrolling only, and sticky footers get repeated — add
/// footer trimming if real pages need it.
struct ScrollStitcher {
    let width: Int
    let height: Int
    /// The stitched picture so far, RGBA rows top to bottom.
    private(set) var pixels: [UInt8] = []
    private var previous: [Row] = []
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

    var stitchedHeight: Int { pixels.count / (width * 4) }

    /// Adds one frame (RGBA8, `width`×`height`, tightly packed).
    mutating func add(_ frame: [UInt8]) -> Step {
        precondition(frame.count == width * height * 4)
        let rows = Self.rows(frame, width: width, height: height)
        defer { previous = rows }
        guard !previous.isEmpty else {
            pixels = frame
            return .first
        }
        guard let shift = Self.shift(from: previous, to: rows) else { return .lost }
        guard shift > 0 else { return .still }
        let room = (maxHeight - stitchedHeight)
        guard room > 0 else { return .full }
        let take = min(shift, room)
        let rowBytes = width * 4
        pixels.append(contentsOf: frame[(height - shift) * rowBytes ..< (height - shift + take) * rowBytes])
        return take < shift ? .full : .added(rows: take)
    }

    func image() -> CGImage? {
        guard !pixels.isEmpty else { return nil }
        let h = stitchedHeight
        return pixels.withUnsafeBytes { buffer -> CGImage? in
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
    static func shift(from a: [Row], to b: [Row]) -> Int? {
        let h = min(a.count, b.count)
        let minOverlap = max(8, h / 8)
        var best: (shift: Int, distance: Float)?
        var all: [Float] = []
        for s in 0...(h - minOverlap) {
            var total: Float = 0, counted = 0
            for k in 0..<(h - s) where !b[k].plain {
                var d: Float = 0
                for i in 0..<blockCount { d += abs(b[k].blocks[i] - a[k + s].blocks[i]) }
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
