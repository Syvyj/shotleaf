import Testing
import AppKit
@testable import CaptureKit

/// Renders the picker into PNGs (no screen involved) when APILA_PREVIEW_DIR is
/// set — for eyeballing the design. Otherwise just checks it draws.
@Suite("Selection overlay render")
@MainActor
struct SelectionPreviewTests {
    /// A fake Retina screen: exactly 2× pixels, drawn in points (top-left origin).
    private func fakeScreen(_ size: CGSize) -> CGImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
        ctx.cgContext.translateBy(x: 0, y: size.height)
        ctx.cgContext.scaleBy(x: 1, y: -1)
        let r = CGRect(origin: .zero, size: size)
        NSGradient(starting: NSColor(srgbRed: 0.93, green: 0.95, blue: 0.98, alpha: 1),
                   ending: NSColor(srgbRed: 0.80, green: 0.86, blue: 0.95, alpha: 1))!.draw(in: r, angle: 90)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: CGRect(x: 120, y: 90, width: 620, height: 420), xRadius: 12, yRadius: 12).fill()
        NSColor(white: 0.2, alpha: 1).setFill()
        for i in 0..<9 {
            NSBezierPath(roundedRect: CGRect(x: 160, y: 140 + i * 38, width: 520 - (i % 3) * 90, height: 14), xRadius: 4, yRadius: 4).fill()
        }
        NSColor.systemOrange.setFill()
        NSBezierPath(ovalIn: CGRect(x: 860, y: 200, width: 160, height: 160)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }

    private func render(_ view: SelectionView, _ name: String) throws {
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        #expect(rep.pixelsWide > 0)
        if let dir = ProcessInfo.processInfo.environment["APILA_PREVIEW_DIR"],
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
    }

    @Test("Draws selection, window highlight and loupe")
    func renders() throws {
        let size = CGSize(width: 1280, height: 800)
        let window = CGRect(x: 120, y: 90, width: 620, height: 420)
        let make = { SelectionView(frame: CGRect(origin: .zero, size: size), image: self.fakeScreen(size), scale: 2,
                                   windows: [window], canRepeat: true) { _ in } }

        let dragging = make()
        dragging.dragStart = CGPoint(x: 150, y: 130)
        dragging.selection = CGRect(x: 150, y: 130, width: 430, height: 180)
        dragging.cursor = CGPoint(x: 580, y: 310)
        try render(dragging, "picker-drag.png")

        let hovering = make()
        hovering.cursor = CGPoint(x: 900, y: 260)
        hovering.hoveredWindow = window
        try render(hovering, "picker-window.png")
    }
}
