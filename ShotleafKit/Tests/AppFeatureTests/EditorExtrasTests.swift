import Testing
import AppKit
@testable import AppFeature

@Suite("Magnifier, pasted pictures, Combine Images, smaller files")
@MainActor
struct EditorExtrasTests {
    /// 100×100 white with a red stripe at x 55…60, at 1 pixel per point.
    private func striped() -> CGImage {
        let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 55, y: 0, width: 5, height: 100))
        return ctx.makeImage()!
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let rep = NSBitmapImageRep(cgImage: image)
        let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        return (Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }

    @Test("The magnifier shows what's under it twice as big, and blurred stays blurred")
    func magnifier() throws {
        let image = striped(), size = CGSize(width: 100, height: 100)
        let loupe = Annotation(kind: .magnify(CGRect(x: 30, y: 30, width: 40, height: 40)), color: .coral)
        let plain = try #require(AnnotationRenderer.export(image, imageSize: size, items: []))
        #expect(pixel(plain, 65, 50).g > 200) // white there without the loupe
        let zoomed = try #require(AnnotationRenderer.export(image, imageSize: size, items: [loupe]))
        let p = pixel(zoomed, 65, 50) // the stripe at 55…60 lands at 60…70
        #expect(p.r > 200 && p.g < 40)

        let blurred = try #require(AnnotationRenderer.export(image, imageSize: size, items: [
            Annotation(kind: .blur(CGRect(x: 50, y: 40, width: 20, height: 20)), color: .coral), loupe,
        ]))
        #expect(pixel(blurred, 65, 50).g > 40) // pixelated with the white around it: never pure red
    }

    @Test("A pasted picture fits in the shot, and resizing keeps its shape")
    func pasted() {
        let frame = AnnotationEditing.pastedFrame(pixels: CGSize(width: 2000, height: 1000), pixelsPerPoint: 2,
                                                  picture: CGSize(width: 800, height: 600))
        #expect(frame == CGRect(x: 160, y: 180, width: 480, height: 240)) // 1000×500 pt shrunk to 60 % of the width
        let small = AnnotationEditing.pastedFrame(pixels: CGSize(width: 64, height: 64), pixelsPerPoint: 2, picture: CGSize(width: 800, height: 600))
        #expect(small.size == CGSize(width: 32, height: 32))

        let kind = Annotation.Kind.image(striped(), CGRect(x: 0, y: 0, width: 200, height: 100))
        guard case .image(_, let r) = AnnotationEditing.resized(kind, .corner(2), to: CGPoint(x: 100, y: 300)) else { Issue.record(); return }
        #expect(r == CGRect(x: 0, y: 0, width: 100, height: 50))
        guard case .image(_, let moved) = AnnotationEditing.moved(kind, by: CGSize(width: 10, height: 5)) else { Issue.record(); return }
        #expect(moved.origin == CGPoint(x: 10, y: 5))
        #expect(AnnotationEditing.hit([Annotation(kind: kind, color: .coral)], at: CGPoint(x: 150, y: 50)) != nil)
    }

    @Test("Combine Images: rows of one height and one width, shaped near 16:10")
    func collage() {
        let (frames, size) = Collage.layout([CGSize(width: 200, height: 100), CGSize(width: 100, height: 100)], columns: 2)
        #expect(frames == [CGRect(x: 0, y: 0, width: 200, height: 100), CGRect(x: 224, y: 0, width: 100, height: 100)])
        #expect(size == CGSize(width: 324, height: 100))

        let squares = Array(repeating: CGSize(width: 500, height: 500), count: 4)
        #expect(Collage.columns(for: squares) == 2)
        let grid = Collage.layout(squares, columns: 2)
        #expect(grid.frames[3] == CGRect(x: 524, y: 524, width: 500, height: 500))

        let combined = Collage.make([striped(), striped()])
        #expect(combined != nil && combined!.width > 100)
    }

    @Test("JPEG under a limit stays under it")
    func smallFile() throws {
        // Noise doesn't compress: the limit must come from lower quality and then a smaller picture.
        let side = 1200
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        var seed: UInt32 = 7
        for i in bytes.indices { seed = seed &* 1_664_525 &+ 1_013_904_223; bytes[i] = UInt8(seed >> 24) }
        let ctx = CGContext(data: &bytes, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let noise = try #require(ctx.makeImage())
        let data = try #require(SmallFile.jpeg(noise, under: 200_000))
        #expect(data.count <= 200_000)
        #expect(NSBitmapImageRep(data: data) != nil)
        #expect(SmallFile.jpeg(striped(), under: 1_000_000)!.count < 20_000) // already small: best quality
    }
}
