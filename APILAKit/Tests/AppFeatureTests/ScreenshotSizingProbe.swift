import Testing
import AppKit
@testable import Core
@testable import AppFeature

@Suite("Screenshot window sizing")
@MainActor
struct ScreenshotSizingTests {
    @Test("A big square capture opens a window that fits its content and the screen")
    func squareCapture() async throws {
        let size = 1600
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGradient(starting: .systemTeal, ending: .systemIndigo)!.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: 30)
        NSGraphicsContext.restoreGraphicsState()
        let windows = ScreenshotWindows()
        windows.show(ImagePayload(data: rep.representation(using: .png, properties: [:])!, width: size, height: size))
        let panel = try #require(windows.open.values.first)
        defer { panel.orderOut(nil) }
        print("SIZING panel", panel.frame, "screens", NSScreen.screens.map(\.visibleFrame))
        // 800×800 pt image + 14 pt padding each side; + header/toolbar/hints below.
        #expect(panel.frame.width == 828)
        #expect(panel.frame.height > 800 && panel.frame.height <= 800 + ScreenshotWindows.chromeHeight)
        #expect(NSScreen.screens.contains { $0.visibleFrame.contains(panel.frame) })

        // It can grow (room around the shot for annotations) and stays grown;
        // it can't shrink below where it started.
        #expect(panel.contentMinSize == panel.frame.size)
        let grown = NSRect(x: panel.frame.minX, y: panel.frame.minY - 200, width: panel.frame.width + 300, height: panel.frame.height + 200)
        panel.setFrame(grown, display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
        #expect(panel.frame.size == grown.size)
        // Shrinking past the minimum — by any path — stops at the minimum.
        panel.setFrame(NSRect(x: grown.minX, y: grown.minY, width: 300, height: 200), display: true)
        #expect(panel.frame.size == panel.contentMinSize)
        if let dir = ProcessInfo.processInfo.environment["APILA_PREVIEW_DIR"], let view = panel.contentView,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("screenshot-grown.png"))
        }
    }
}

@Suite("Edge resizing")
@MainActor
struct EdgeResizerTests {
    @Test("The band catches edges and corners; the inside passes clicks through")
    func band() {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let edge = WindowEdgeResizer.EdgeView(frame: parent.bounds)
        parent.addSubview(edge)
        #expect(edge.hitTest(NSPoint(x: 200, y: 150)) == nil)
        #expect(edge.hitTest(NSPoint(x: 2, y: 150)) === edge)
        #expect(edge.hitTest(NSPoint(x: 398, y: 150)) === edge)
        #expect(edge.edges(at: NSPoint(x: 2, y: 2)) == [.left, .top])       // flipped: top-left corner
        #expect(edge.edges(at: NSPoint(x: 398, y: 298)) == [.right, .bottom])
        #expect(edge.edges(at: NSPoint(x: 200, y: 150)).isEmpty)
    }
}
