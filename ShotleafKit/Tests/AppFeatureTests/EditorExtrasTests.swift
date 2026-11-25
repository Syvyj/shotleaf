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
    func smallFile() async throws {
        // Noise doesn't compress: the limit must come from lower quality and then a smaller picture.
        let side = 1200
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        var seed: UInt32 = 7
        for i in bytes.indices { seed = seed &* 1_664_525 &+ 1_013_904_223; bytes[i] = UInt8(seed >> 24) }
        let ctx = CGContext(data: &bytes, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let noise = try #require(ctx.makeImage())
        let data = try #require(await SmallFile.jpeg(noise, under: 200_000))
        #expect(data.count <= 200_000)
        #expect(NSBitmapImageRep(data: data) != nil)
        #expect(await SmallFile.jpeg(striped(), under: 1_000_000)!.count < 20_000) // already small: best quality
    }

    private func blank(_ w: Int, _ h: Int) -> CGImage {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }

    @Test("Minus shrinks by 25% and stops at 10% of the original")
    func minusShrinksBy25PercentDownTo10Percent() throws {
        let image = blank(1000, 800), doc = AnnotationDocument()
        doc.add(.rectangle(CGRect(x: 100, y: 100, width: 200, height: 40)))
        doc.resize(original: image, factor: 0.75)
        #expect(doc.base?.image.width == 750 && doc.base?.image.height == 600)
        #expect(doc.base?.size == CGSize(width: 750, height: 600))
        #expect(doc.items[0].kind == .rectangle(CGRect(x: 75, y: 75, width: 150, height: 30))) // marks follow
        for _ in 0..<30 { doc.resize(original: image, factor: 0.75) }
        #expect(doc.base?.image.width == 100 && doc.base?.image.height == 80)
    }

    @Test("Undo brings the size back")
    func undoRestoresSize() {
        let image = blank(1000, 800), doc = AnnotationDocument()
        doc.add(.rectangle(CGRect(x: 100, y: 100, width: 200, height: 40)))
        doc.resize(original: image, factor: 0.75)
        doc.undo()
        #expect(doc.base == nil)
        #expect(doc.items[0].kind == .rectangle(CGRect(x: 100, y: 100, width: 200, height: 40)))
    }

    @Test("A preset fits the long side, and a bigger one is off")
    func presetFitsLongSide() {
        let image = blank(3000, 1000), doc = AnnotationDocument()
        #expect(doc.canResize(original: image, toLongSide: 1280))
        doc.resize(original: image, toLongSide: 1280)
        #expect(doc.base?.image.width == 1280 && doc.base?.image.height == 427)
        #expect(!doc.canResize(original: image, toLongSide: 1920))
        doc.resize(original: image, toLongSide: 1920)
        #expect(doc.base?.image.width == 1280)
    }

    @Test("A preset on a retina shot keeps the point size ratio and the marks in place")
    func presetOnRetina() {
        let image = blank(2000, 1000), doc = AnnotationDocument()
        doc.add(.rectangle(CGRect(x: 100, y: 50, width: 200, height: 100)))
        doc.resize(original: image, toLongSide: 1280, size: CGSize(width: 1000, height: 500))
        #expect(doc.base?.image.width == 1280 && doc.base?.image.height == 640)
        #expect(doc.base?.size == CGSize(width: 640, height: 320))
        #expect(doc.items[0].kind == .rectangle(CGRect(x: 64, y: 32, width: 128, height: 64)))
    }

    @Test("Choosing a ratio constrains the crop already drawn")
    func ratioOnExistingCrop() throws {
        let doc = AnnotationDocument()
        let id = doc.add(.crop(CGRect(x: 10, y: 10, width: 400, height: 400)))
        let view = ScreenshotView(image: NSImage(size: CGSize(width: 500, height: 500)), cgImage: blank(500, 500),
                                  pixelSize: CGSize(width: 500, height: 500), displaySize: CGSize(width: 500, height: 500),
                                  actions: ScreenshotActions(copy: {}, save: { nil }, pin: {}, close: {}, dragFile: { nil }), doc: doc)
        view.setCropAspect(.wide16x9)
        guard case .crop(let r)? = doc.items.first(where: { $0.id == id })?.kind else { Issue.record("no crop"); return }
        #expect(abs(r.width / r.height - 16.0 / 9) < 0.01)
        #expect(r.minX == 10 && r.minY == 10)
    }

    @Test("A cropped rectangle keeps the aspect inside the original")
    func constrainedKeepsAspect() {
        let source = CGRect(x: 0, y: 0, width: 500, height: 500)
        let r = AnnotationEditing.constrained(source, to: .wide16x9)
        #expect(abs(r.width / r.height - 16.0 / 9) < 0.01)
        #expect(source.contains(r))
        #expect(AnnotationEditing.constrained(source, to: .free) == source)
    }

    @Test("The minus key is not a tool key")
    func minusKeyIsFree() {
        #expect(AnnotationTool.allCases.allSatisfy { $0.defaultKey != "-" })
    }
}

@Suite("Saving and links never lose a shot")
@MainActor
struct SaveAndLinkTests {
    @Test("Two saves in the same second keep both files")
    func twoSaves() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shotleaf-save-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        let first = try #require(ScreenshotWindows.save(Data([1]), to: dir, now: now))
        let second = try #require(ScreenshotWindows.save(Data([2]), to: dir, now: now))
        #expect(first != second && second.deletingPathExtension().lastPathComponent.hasSuffix(" 2"))
        #expect(try Data(contentsOf: first) == Data([1]) && Data(contentsOf: second) == Data([2]))
    }

    @Test("Undo keeps the last 50 steps")
    func undoLimit() {
        let doc = AnnotationDocument()
        for i in 0..<60 { doc.add(.step(center: CGPoint(x: i, y: i), number: i + 1)) }
        var steps = 0
        while doc.canUndo { doc.undo(); steps += 1 }
        #expect(steps == AnnotationDocument.undoLimit && doc.items.count == 10)
    }
}

/// Off the main actor: making a 7 MB picture takes a while.
@Suite("Links for big shots")
struct BigLinkTests {
    @Test("A PNG too big for the free link service goes as a JPEG that fits; an own server gets it as it is")
    func fitted() async throws {
        let side = 1400 // random noise: a PNG well over 5 MB
        var bytes = (0..<side * side * 4).map { _ in UInt8.random(in: 0...255) }
        let picture = try #require(bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        })
        let png = try #require(NSBitmapImageRep(cgImage: picture).representation(using: .png, properties: [:]))
        try #require(png.count > ShotLinks.freeLimit)
        let sent = await ShotLinks.fitted(png, server: ShotLinks.freeService)
        #expect(sent.count <= ShotLinks.freeLimit && sent.prefix(3) == Data([0xFF, 0xD8, 0xFF]))
        #expect(await ShotLinks.fitted(png, server: "https://shots.example.com") == png)
        #expect(await ShotLinks.fitted(Data([1, 2, 3]), server: ShotLinks.freeService) == Data([1, 2, 3]))
        // A limit nothing can meet gives nothing, never a file over the limit.
        let big = try #require(NSBitmapImageRep(data: png)?.cgImage)
        #expect(await SmallFile.jpeg(big, under: 100) == nil)
    }
}
