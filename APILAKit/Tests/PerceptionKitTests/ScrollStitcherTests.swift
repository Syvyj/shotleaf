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
