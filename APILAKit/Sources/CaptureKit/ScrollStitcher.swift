import CoreGraphics
import Foundation

/// Glues frames of a scrolling area into one tall image (unit-tested).
///
/// Each frame is compared with the previous one row by row (rows hashed,
/// edges left out so an overlay scrollbar doesn't spoil the match). The shift
/// where the most rows line up is how far the content scrolled; the rows that
/// scrolled in at the bottom are appended.
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

    struct Row: Equatable {
        let hash: Int
        /// One color across the row: matches anything, so it doesn't count.
        let plain: Bool
    }

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
        return frame.withUnsafeBytes { raw in
            let px = raw.bindMemory(to: UInt32.self)
            return (0..<height).map { y in
                let base = y * width
                let first = px[base + from] & 0x00FF_FFFF
                var hash: UInt64 = 0xcbf2_9ce4_8422_2325 // FNV-1a
                var plain = true
                for x in stride(from: from, to: to, by: 2) {
                    let v = px[base + x] & 0x00FF_FFFF // ignore alpha
                    hash = (hash ^ UInt64(v)) &* 0x0000_0100_0000_01B3
                    if v != first { plain = false }
                }
                return Row(hash: Int(truncatingIfNeeded: hash), plain: plain)
            }
        }
    }

    /// How many rows the content moved up between `a` and `b`: 0 = still,
    /// nil = no convincing overlap.
    static func shift(from a: [Row], to b: [Row]) -> Int? {
        let h = min(a.count, b.count)
        let minOverlap = max(8, h / 8)
        var best: (shift: Int, score: Double)?
        for s in 0...(h - minOverlap) {
            var matched = 0, counted = 0
            for k in 0..<(h - s) where !b[k].plain {
                counted += 1
                if b[k].hash == a[k + s].hash { matched += 1 }
            }
            guard counted >= 4 else { continue }
            let score = Double(matched) / Double(counted)
            if score > (best?.score ?? 0) + 0.0001 { best = (s, score) }
        }
        guard let best, best.score >= 0.6 else { return nil }
        return best.shift
    }
}
