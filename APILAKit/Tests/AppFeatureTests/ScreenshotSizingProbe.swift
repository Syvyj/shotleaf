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
        let windows = ScreenshotWindows()
        windows.show(ImagePayload(data: rep.representation(using: .png, properties: [:])!, width: size, height: size))
        let panel = try #require(windows.open.values.first)
        defer { panel.orderOut(nil) }
        print("SIZING panel", panel.frame, "screens", NSScreen.screens.map(\.visibleFrame))
        // 800×800 pt image + 14 pt padding each side; + header/toolbar/hints below.
        #expect(panel.frame.width == 828)
        #expect(panel.frame.height > 800 && panel.frame.height <= 800 + ScreenshotWindows.chromeHeight)
        #expect(NSScreen.screens.contains { $0.visibleFrame.contains(panel.frame) })
    }
}
