import Testing
import SwiftUI
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
    }
}
