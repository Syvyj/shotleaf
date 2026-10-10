import Testing
@testable import CaptureKit

@Suite("Scroll stitching")
struct ScrollStitcherTests {
    /// A fake 60-px-wide "page": blank margins, rows with varied "text", and
    /// some plain gaps between paragraphs.
    static func page(height: Int, width: Int = 60) -> [UInt8] {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        var seed: UInt32 = 7
        for y in 0..<height where y % 23 < 17 { // paragraph gaps stay plain white
            for x in 8..<(width - 8) {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let v = UInt8(truncatingIfNeeded: seed >> 24)
                let i = (y * width + x) * 4
                bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v
            }
        }
        return bytes
    }

    static func window(_ page: [UInt8], at top: Int, height: Int, width: Int = 60) -> [UInt8] {
        Array(page[top * width * 4 ..< (top + height) * width * 4])
    }

    @Test("Frames scrolled by different amounts glue back into the page")
    func stitches() {
        let page = Self.page(height: 1000)
        var s = ScrollStitcher(width: 60, height: 200)
        #expect(s.add(Self.window(page, at: 0, height: 200)) == .first)
        #expect(s.add(Self.window(page, at: 37, height: 200)) == .added(rows: 37))
        #expect(s.add(Self.window(page, at: 37, height: 200)) == .still)
        #expect(s.add(Self.window(page, at: 150, height: 200)) == .added(rows: 113))
        #expect(s.add(Self.window(page, at: 310, height: 200)) == .added(rows: 160)) // overlap 40 rows is still enough
        #expect(s.stitchedHeight == 510)
        let same = s.pixels == Array(page[0 ..< 510 * 60 * 4])
        #expect(same)
    }

    @Test("Smooth scrolling: a frame half a pixel between two rows still matches")
    func subpixel() {
        // Real text is soft from row to row (antialiasing): blur the fake page vertically.
        let rough = Self.page(height: 1000), w4 = 60 * 4
        let page = rough.indices.map { i in
            let rows = [i - 2 * w4, i - w4, i, i + w4, i + 2 * w4].filter(rough.indices.contains)
            return UInt8(rows.reduce(0) { $0 + Int(rough[$1]) } / rows.count)
        }
        let a = Self.window(page, at: 37, height: 200), b = Self.window(page, at: 38, height: 200)
        let blurred = zip(a, b).map { UInt8((Int($0) + Int($1)) / 2) }
        var s = ScrollStitcher(width: 60, height: 200)
        _ = s.add(Self.window(page, at: 0, height: 200))
        let step = s.add(blurred)
        #expect(step == .added(rows: 37) || step == .added(rows: 38), "\(step)")
    }

    @Test("Sticky header and footer: matched around, the footer kept once at the end")
    func sticky() throws {
        let page = Self.page(height: 1000)
        let w = 60 * 4
        func bar(_ rows: Int, _ v: UInt8) -> [UInt8] {
            (0..<rows * 60).flatMap { i in i % 7 == 0 ? [0, 0, 0, 255] : [v, v, v, 255] } // a striped, non-plain bar
        }
        let top = bar(20, 90), bottom = bar(30, 200)
        func frame(_ at: Int) -> [UInt8] { top + Array(page[(at + 20) * w ..< (at + 170) * w]) + bottom }
        var s = ScrollStitcher(width: 60, height: 200)
        _ = s.add(frame(0))
        #expect(s.add(frame(40)) == .added(rows: 40))
        #expect(s.add(frame(100)) == .added(rows: 60))
        // header + page rows 20..<270 (frame 0 showed 20..<170, then +100) + footer
        #expect(s.stitchedHeight == 20 + 250 + 30)
        let image = try #require(s.image())
        #expect(image.height == 300)
        let data = Array(s.pixels + bottom)
        #expect(Array(data[(20 + 250) * w ..< 300 * w]) == bottom)
        #expect(Array(s.pixels[20 * w ..< 270 * w]) == Array(page[20 * w ..< 270 * w]))
    }

    @Test("A jump past one frame is reported, not glued wrong")
    func lost() {
        let page = Self.page(height: 1000)
        var s = ScrollStitcher(width: 60, height: 200)
        _ = s.add(Self.window(page, at: 0, height: 200))
        #expect(s.add(Self.window(page, at: 600, height: 200)) == .lost)
        #expect(s.stitchedHeight == 200)
    }

    @Test("Stops at the height limit")
    func full() {
        let page = Self.page(height: 1000)
        var s = ScrollStitcher(width: 60, height: 200, maxHeight: 260)
        _ = s.add(Self.window(page, at: 0, height: 200))
        #expect(s.add(Self.window(page, at: 100, height: 200)) == .full)
        #expect(s.stitchedHeight == 260)
        #expect(s.image()?.height == 260)
    }
}
