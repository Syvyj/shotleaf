import Testing
import SwiftUI
import UniformTypeIdentifiers
@testable import Core
@testable import PerceptionKit
@testable import AppFeature

@Suite("Screenshot window")
@MainActor
struct ScreenshotWindowTests {
    static let blankImage: CGImage = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!

    @Test("File name is sortable and Finder-safe")
    func fileName() {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 8; c.hour = 16; c.minute = 5; c.second = 9
        let date = Calendar.current.date(from: c)!
        #expect(ScreenshotWindows.fileName(date) == "APILA 2026-10-08 at 16.05.09.png")
        #expect(ScreenshotWindows.fileName(date, template: "shot {date}/{time}") == "shot 2026-10-08-16.05.09.png")
        #expect(ScreenshotWindows.fileName(date, template: "  ") == "APILA 2026-10-08 at 16.05.09.png")
    }

    @Test("Preview scales big captures down to the room, never up")
    func fit() {
        let room = CGSize(width: 1000, height: 800)
        #expect(ScreenshotWindows.fit(points: CGSize(width: 200, height: 100), in: room) == CGSize(width: 200, height: 100))
        #expect(ScreenshotWindows.fit(points: CGSize(width: 2000, height: 1000), in: room) == CGSize(width: 1000, height: 500))
        // A tall phone-like capture (1056×2436 px @2x) shrinks to the height.
        #expect(ScreenshotWindows.fit(points: CGSize(width: 528, height: 1218), in: room).height == 800)
    }

    @Test("chromeHeight really covers header + toolbar + hints")
    func chrome() {
        let display = CGSize(width: 340, height: 780)
        let noop = ScreenshotActions(copy: {}, save: { nil }, pin: {}, close: {}, dragFile: { nil })
        let host = NSHostingView(rootView: ScreenshotView(
            image: NSImage(size: display), cgImage: Self.blankImage, pixelSize: CGSize(width: 680, height: 1560),
            displaySize: display, actions: noop, doc: AnnotationDocument()))
        let extra = host.fittingSize.height - display.height - 2 * ScreenshotView.margin
        #expect(extra > 0 && extra <= ScreenshotWindows.chromeHeight, "chrome is \(extra) pt")
    }

    @Test("A tiny shot with a crop: rows fit the minimum width without squeezing")
    func narrow() throws {
        let display = CGSize(width: 260, height: 160)
        let doc = AnnotationDocument()
        doc.add(.crop(CGRect(x: 10, y: 10, width: 100, height: 60)))
        let noop = ScreenshotActions(copy: {}, save: { nil }, pin: {}, close: {}, dragFile: { nil })
        let view = ScreenshotView(image: NSImage(size: display), cgImage: Self.blankImage, pixelSize: CGSize(width: 520, height: 320),
                                  displaySize: display, actions: noop, doc: doc)
        let fit = NSHostingView(rootView: view).fittingSize
        #expect(fit.width <= ScreenshotView.minContentWidth + 28 + 0.5, "width \(fit.width)")
        let chrome = fit.height - display.height - 2 * ScreenshotView.margin
        #expect(chrome <= ScreenshotWindows.chromeHeight, "chrome \(chrome)")
        try renderPreview(view, "screenshot-narrow.png")
    }

    @Test("Window is kept inside the screen even when it's taller than the centre allows")
    func placement() {
        let visible = CGRect(x: 0, y: 25, width: 1512, height: 920)
        let p = ScreenshotWindows.placed(CGSize(width: 600, height: 900), centeredIn: visible)
        #expect(p.y >= visible.minY && p.y + 900 <= visible.maxY)
        #expect(p.x >= visible.minX && p.x + 600 <= visible.maxX)
    }

    @Test("Save writes the PNG into the folder")
    func save() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("apila-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try #require(ScreenshotWindows.save(Data([1, 2, 3]), to: dir))
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
    }

    @Test("Text from a screenshot: an editable window, sized to its content")
    func textWindow() throws {
        let view = TextResultView(text: "Зустріч о 15:00 біля офісу\nAgenda: Q3 report, budget", title: "Text from Screenshot",
                                  copy: { _ in }, close: {})
        let size = NSHostingView(rootView: view).fittingSize
        #expect(size.width >= 460 && size.height >= 280)
        try renderPreview(view, "text-window.png")
    }

    @Test("Renders (design preview when APILA_PREVIEW_DIR is set)")
    func render() throws {
        let image = NSImage(size: NSSize(width: 640, height: 360), flipped: false) { r in
            NSGradient(starting: .systemTeal, ending: .systemIndigo)!.draw(in: r, angle: 30)
            ("Shottr-level APILA" as NSString).draw(at: NSPoint(x: 40, y: 160), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 40), .foregroundColor: NSColor.white])
            return true
        }
        let noop = ScreenshotActions(copy: {}, save: { nil }, pin: {}, close: {}, dragFile: { nil })
        var rect = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let cg = try #require(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        let doc = AnnotationDocument()
        doc.add(.arrow(from: CGPoint(x: 460, y: 80), to: CGPoint(x: 330, y: 160)))
        doc.color = .amber
        doc.add(.rectangle(CGRect(x: 30, y: 140, width: 300, height: 70)))
        doc.add(.step(center: CGPoint(x: 30, y: 140), number: 1))
        doc.color = .white
        doc.add(.text(origin: CGPoint(x: 360, y: 240), string: "look here — a long note wraps onto the next line", tail: CGPoint(x: 330, y: 300)))
        doc.add(.blur(CGRect(x: 480, y: 280, width: 140, height: 60)))
        doc.add(.focus(CGRect(x: 20, y: 120, width: 340, height: 120)))
        doc.color = .leaf
        doc.add(.measure(from: CGPoint(x: 30, y: 330), to: CGPoint(x: 330, y: 330)))
        doc.color = .coral
        doc.lineWidth = 7
        let thick = doc.add(.arrow(from: CGPoint(x: 600, y: 330), to: CGPoint(x: 470, y: 230)))
        doc.selection = thick
        doc.tool = .arrow
        let view = ScreenshotView(image: image, cgImage: cg, pixelSize: CGSize(width: 1280, height: 720),
                                  displaySize: CGSize(width: 640, height: 360), actions: noop, doc: doc)
        try renderPreview(view, "screenshot-window.png")
        doc.color = .sky
        doc.add(.ellipse(CGRect(x: 380, y: 40, width: 160, height: 90)))
        doc.add(.crop(CGRect(x: 10, y: 20, width: 560, height: 300)))
        try renderPreview(view, "screenshot-crop.png")
        doc.applyCrop(original: cg, size: CGSize(width: 640, height: 360))
        try renderPreview(view, "screenshot-cropped.png")
        try renderPreview(view, "screenshot-window-dark.png", dark: true)
        doc.lineWidth = 4
        doc.add(.pen([CGPoint(x: 40, y: 40), CGPoint(x: 80, y: 20), CGPoint(x: 140, y: 60), CGPoint(x: 200, y: 30)]))
        doc.backdrop = Backdrop(fill: .gradient(1))
        doc.watermark = Watermark(text: "© APILA", position: 8, size: 0.3, opacity: 0.7, rotation: -12)
        try renderPreview(view, "screenshot-backdrop.png")
    }
}

@Suite("Pen, background, formats")
@MainActor
struct PenBackdropTests {
    @Test("Watermark lands in its corner of the export")
    func watermark() throws {
        let black = try #require(CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        black.setFillColor(.black); black.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        let shot = try #require(black.makeImage())
        let out = try #require(AnnotationRenderer.export(shot, imageSize: CGSize(width: 400, height: 200), items: [],
                                                          watermark: Watermark(text: "APILA", position: 8, size: 0.4, opacity: 1)))
        let rep = NSBitmapImageRep(cgImage: out)
        func brightness(_ x: ClosedRange<Int>, _ y: ClosedRange<Int>) -> CGFloat {
            var sum: CGFloat = 0
            for i in x { for j in y { sum += rep.colorAt(x: i, y: j)?.brightnessComponent ?? 0 } }
            return sum
        }
        #expect(brightness(230...390, 130...190) > 50)   // bottom-right: the white text
        #expect(brightness(10...170, 10...70) == 0)        // top-left: untouched
    }

    @Test("Tool keys: a taken key moves over, editor keys are refused, order moves")
    func toolPrefs() {
        defer { ToolPrefs.reset() }
        ToolPrefs.reset()
        #expect(ToolPrefs.setKey("D", for: .arrow))
        #expect(AnnotationTool.arrow.key == "d" && AnnotationTool.pen.key == nil)
        #expect(!ToolPrefs.setKey("p", for: .blur) && AnnotationTool.blur.key == "5")
        #expect(ToolPrefs.setKey("", for: .blur) && AnnotationTool.blur.key == nil)
        ToolPrefs.move(.rectangle, by: -1)
        #expect(Array(AnnotationTool.ordered.prefix(2)) == [.rectangle, .arrow])
    }

    @Test("Recent screenshots: newest first, only the last ten kept")
    func recent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("apila-recent-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let shot = ImagePayload(data: Data([1]), width: 1, height: 1)
        var list: [URL] = []
        for i in 0..<12 { list = ScreenshotWindows.remember(shot, in: dir, now: Date(timeIntervalSince1970: Double(i) * 60)) }
        #expect(list.count == 10 && ScreenshotWindows.recent(in: dir).count == 10)
        #expect(list.first!.lastPathComponent > list.last!.lastPathComponent)
    }

    @Test("1x halves a Retina PNG; image data becomes a PNG payload with its pixel size")
    func oneXAndPayload() throws {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 20, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let half = try #require(NSBitmapImageRep(data: ScreenshotWindows.oneX(png, scale: 2)))
        #expect(half.pixelsWide == 20 && half.pixelsHigh == 10)
        #expect(ScreenshotWindows.oneX(png, scale: 1) == png)
        let tiff = try #require(rep.tiffRepresentation)
        let payload = try #require(ScreenshotWindows.payload(fromImageData: tiff))
        #expect(payload.width == 40 && payload.height == 20)
    }

    @Test("Pen: hit along the line, moves as a whole; tool keys keep their numbers")
    func pen() {
        let line = Annotation.Kind.pen([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)])
        #expect(AnnotationEditing.contains(line, CGPoint(x: 50, y: 3)))
        #expect(!AnnotationEditing.contains(line, CGPoint(x: 50, y: 50)))
        #expect(AnnotationEditing.moved(line, by: CGSize(width: 10, height: 5)) == .pen([CGPoint(x: 10, y: 5), CGPoint(x: 110, y: 5), CGPoint(x: 110, y: 105)]))
        #expect(AnnotationTool.arrow.key == "1" && AnnotationTool.blur.key == "5" && AnnotationTool.focus.key == "9" && AnnotationTool.pen.key == "d")
        #expect(Set(AnnotationTool.allCases.map(\.key)).count == AnnotationTool.allCases.count)
    }

    @Test("Background frames the shot with padding (in pixels) and keeps it opaque")
    func backdrop() throws {
        let shot = try #require(CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        let framed = try #require(Backdrop(fill: .solid(3), padding: 40, corner: 10).framed(shot, scale: 2))
        #expect(framed.width == 360 && framed.height == 260)
    }

    @Test("Save as: JPEG, HEIC and PDF come out readable")
    func formats() throws {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 20, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = try #require(rep.representation(using: .png, properties: [:]))
        for type in [UTType.jpeg, .heic] {
            let data = try #require(ScreenshotWindows.encoded(png, as: type, scale: 2))
            #expect(NSImage(data: data)?.size.width ?? 0 > 0, "\(type)")
        }
        let pdf = try #require(ScreenshotWindows.encoded(png, as: .pdf, scale: 2))
        #expect(PDFPageSize(pdf) == CGSize(width: 20, height: 10))
    }

    private func PDFPageSize(_ data: Data) -> CGSize? {
        CGPDFDocument(CGDataProvider(data: data as CFData)!)?.page(at: 1)?.getBoxRect(.mediaBox).size
    }
}

@Suite("Sounds")
struct SoundTests {
    @Test("Synthesized sounds are short, unclipped and load as WAV")
    func synth() {
        for samples in [Synth.shutter(), Synth.bloop()] {
            let peak = samples.map(abs).max() ?? 0
            #expect(peak > 0.1 && peak <= 1, "peak \(peak)")
            #expect(Double(samples.count) / Synth.rate < 0.25)
            #expect(NSSound(data: Synth.wav(samples)) != nil)
        }
    }
}
