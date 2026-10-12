import Testing
import AppKit
@testable import AppFeature

/// Pixel-level checks of what Copy/Save/Pin produce.
@Suite("Annotation export")
@MainActor
struct AnnotationExportTests {
    /// 200×100 px "screenshot" at 2× (100×50 pt): white, with a black bar
    /// (fake text) at x 40–60 pt, y 20–30 pt, and a red square at x 80–90.
    private func shot() -> CGImage {
        let ctx = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // CG origin is bottom-left; convert y-down points to pixels.
        func fill(_ r: CGRect, _ c: NSColor) { ctx.setFillColor(c.cgColor); ctx.fill(CGRect(x: r.minX * 2, y: 100 - r.maxY * 2, width: r.width * 2, height: r.height * 2)) }
        fill(CGRect(x: 0, y: 0, width: 100, height: 50), .white)
        fill(CGRect(x: 40, y: 20, width: 20, height: 10), .black)
        fill(CGRect(x: 80, y: 10, width: 10, height: 10), .red)
        return ctx.makeImage()!
    }
    private let size = CGSize(width: 100, height: 50)

    /// RGB at a y-down point of an exported image (2 px per point).
    private func rgb(_ image: CGImage, _ p: CGPoint, origin: CGPoint = .zero) -> (Int, Int, Int) {
        let rep = NSBitmapImageRep(cgImage: image)
        let c = rep.colorAt(x: Int((p.x - origin.x) * 2), y: Int((p.y - origin.y) * 2))!.usingColorSpace(.sRGB)!
        return (Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }

    @Test("Marks inside the image keep the export at image size")
    func boundsInside() {
        let doc = [Annotation(kind: .rectangle(CGRect(x: 10, y: 10, width: 20, height: 20)), color: .coral)]
        #expect(AnnotationRenderer.exportBounds(doc, imageSize: size) == CGRect(origin: .zero, size: size))
    }

    @Test("A mark on the canvas outside the image grows the export to include it")
    func boundsOutside() throws {
        let items = [Annotation(kind: .arrow(from: CGPoint(x: 150, y: 25), to: CGPoint(x: 90, y: 25)), color: .coral)]
        let b = AnnotationRenderer.exportBounds(items, imageSize: size)
        #expect(b.maxX > 150 && b.minX == 0)
        let out = try #require(AnnotationRenderer.export(shot(), imageSize: size, items: items))
        #expect(out.width == Int(b.width * 2))
    }

    @Test("Erase wipes the fake text with the surrounding white")
    func erase() throws {
        let image = shot()
        let r = CGRect(x: 36, y: 16, width: 28, height: 18)
        let fill = AnnotationRenderer.surroundingColor(of: r, image: image, imageSize: size)
        #expect(fill.usingColorSpace(.sRGB)!.redComponent > 0.95)
        let out = try #require(AnnotationRenderer.export(image, imageSize: size, items: [Annotation(kind: .erase(r, fill: fill), color: .coral)]))
        let (red, green, blue) = rgb(out, CGPoint(x: 50, y: 25))
        #expect(red > 240 && green > 240 && blue > 240)
    }

    @Test("Cut moves the red square and leaves background behind")
    func cut() throws {
        let image = shot()
        let source = CGRect(x: 78, y: 8, width: 14, height: 14)
        let fill = AnnotationRenderer.surroundingColor(of: source, image: image, imageSize: size)
        let item = Annotation(kind: .piece(source: source, offset: CGSize(width: -60, height: 20), fill: fill), color: .coral)
        let out = try #require(AnnotationRenderer.export(image, imageSize: size, items: [item]))
        let old = rgb(out, CGPoint(x: 85, y: 15))
        let new = rgb(out, CGPoint(x: 25, y: 35))
        #expect(old.0 > 240 && old.1 > 240)              // white where it was
        #expect(new.0 > 200 && new.1 < 60 && new.2 < 60) // red where it went
    }

    @Test("Blur pixelates: a sharp edge inside the area gets averaged")
    func blur() throws {
        let image = shot()
        let r = CGRect(x: 33, y: 13, width: 40, height: 30) // covers the bar; cells not aligned with it
        let out = try #require(AnnotationRenderer.export(image, imageSize: size, items: [Annotation(kind: .blur(r), color: .coral)]))
        // Some pixel in the area is now neither pure black nor pure white.
        let mixed = stride(from: 31.0, to: 69.0, by: 1.0).contains { x in
            let (red, _, _) = rgb(out, CGPoint(x: x, y: 25))
            return red > 20 && red < 235
        }
        #expect(mixed)
    }

    @Test("Undo/redo and step numbering")
    func document() {
        let doc = AnnotationDocument()
        doc.add(.step(center: .zero, number: doc.nextStep))
        doc.add(.step(center: .zero, number: doc.nextStep))
        #expect(doc.nextStep == 3)
        #expect(doc.items.map(\.color) == [.coral, .amber], "each step gets the next color")
        doc.undo()
        #expect(doc.items.count == 1 && doc.nextStep == 2 && doc.canRedo)
        doc.redo()
        #expect(doc.items.count == 2 && !doc.canRedo)
    }
}

@Suite("Crop & oval")
@MainActor
struct CropTests {
    @Test("Crop: export is exactly the crop; a new crop replaces the old one")
    func crop() throws {
        let doc = AnnotationDocument()
        doc.add(.crop(CGRect(x: 10, y: 10, width: 40, height: 20)))
        doc.add(.crop(CGRect(x: 20, y: 5, width: 30, height: 30)))
        #expect(doc.items.count == 1 && doc.crop == CGRect(x: 20, y: 5, width: 30, height: 30))
        #expect(AnnotationRenderer.exportBounds(doc.items, imageSize: CGSize(width: 100, height: 50)) == CGRect(x: 20, y: 5, width: 30, height: 30))
        let ctx = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let out = try #require(AnnotationRenderer.export(ctx.makeImage()!, imageSize: CGSize(width: 100, height: 50), items: doc.items))
        #expect(out.width == 60 && out.height == 60) // 30×30 pt at 2×
    }

    @Test("Crop is picked by its border, so marks inside stay clickable")
    func cropHit() {
        let crop: Annotation.Kind = .crop(CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(AnnotationEditing.contains(crop, CGPoint(x: 0, y: 50)))
        #expect(!AnnotationEditing.contains(crop, CGPoint(x: 50, y: 50)))
    }

    @Test("Oval resizes by its corners like a box")
    func oval() {
        let oval: Annotation.Kind = .ellipse(CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(AnnotationEditing.resized(oval, .corner(2), to: CGPoint(x: 30, y: 20)) == .ellipse(CGRect(x: 0, y: 0, width: 30, height: 20)))
        #expect(AnnotationTool.ellipse.key == "o" && AnnotationTool.crop.key == "c" && AnnotationTool.focus.key == "9")
    }
}

@Suite("Apply crop")
@MainActor
struct ApplyCropTests {
    @Test("Keeps only the crop, shifts marks with it, and undo brings it all back")
    func apply() throws {
        let ctx = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let original = ctx.makeImage()!
        let size = CGSize(width: 100, height: 50)
        let doc = AnnotationDocument()
        doc.add(.arrow(from: CGPoint(x: 30, y: 20), to: CGPoint(x: 50, y: 30)))
        doc.add(.crop(CGRect(x: 20, y: 10, width: 40, height: 30)))

        doc.applyCrop(original: original, size: size)
        let base = try #require(doc.base)
        #expect(base.size == CGSize(width: 40, height: 30))
        #expect(base.image.width == 80 && base.image.height == 60) // 2× pixels kept
        #expect(doc.crop == nil && doc.items.count == 1)
        #expect(doc.items[0].kind == .arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 20)))

        doc.undo()
        #expect(doc.base == nil && doc.crop != nil && doc.items.count == 2)
        doc.redo()
        #expect(doc.base?.size == CGSize(width: 40, height: 30))
    }
}
