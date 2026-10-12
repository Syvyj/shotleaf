import Testing
import CoreGraphics
@testable import CaptureKit

@Suite("Capture geometry")
struct CaptureGeometryTests {
    @Test("Drag in any direction gives the same rect")
    func dragRect() {
        let r = CaptureGeometry.rect(from: CGPoint(x: 50, y: 80), to: CGPoint(x: 10, y: 20))
        #expect(r == CGRect(x: 10, y: 20, width: 40, height: 60))
    }

    @Test("Window on a second display maps into that display's view")
    func secondDisplay() {
        // Second display sits to the right of a 1512-pt-wide primary, 200 pt lower.
        let screen = CGRect(x: 1512, y: 200, width: 1920, height: 1080)
        let window = CGRect(x: 1612, y: 250, width: 800, height: 600)
        #expect(CaptureGeometry.viewRect(fromGlobal: window, screen: screen) == CGRect(x: 100, y: 50, width: 800, height: 600))
    }

    @Test("Points → Retina pixels, clamped to the image")
    func pixels() {
        let image = CGSize(width: 200, height: 100)
        #expect(CaptureGeometry.pixelRect(fromView: CGRect(x: 10, y: 5, width: 20, height: 10), scale: 2, imageSize: image)
                == CGRect(x: 20, y: 10, width: 40, height: 20))
        #expect(CaptureGeometry.pixelRect(fromView: CGRect(x: 90, y: 40, width: 50, height: 50), scale: 2, imageSize: image)
                == CGRect(x: 180, y: 80, width: 20, height: 20))
    }

    @Test("Topmost window wins; empty space has none")
    func hitTest() {
        let front = CGRect(x: 0, y: 0, width: 100, height: 100)
        let back = CGRect(x: 0, y: 0, width: 500, height: 500)
        #expect(CaptureGeometry.window(at: CGPoint(x: 50, y: 50), in: [front, back]) == front)
        #expect(CaptureGeometry.window(at: CGPoint(x: 300, y: 300), in: [front, back]) == back)
        #expect(CaptureGeometry.window(at: CGPoint(x: 900, y: 900), in: [front, back]) == nil)
    }

    @Test("Loupe flips to stay on screen near the edges")
    func loupe() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 132, height: 160)
        #expect(CaptureGeometry.loupeOrigin(cursor: CGPoint(x: 100, y: 100), loupe: size, bounds: bounds) == CGPoint(x: 124, y: 124))
        let corner = CaptureGeometry.loupeOrigin(cursor: CGPoint(x: 990, y: 790), loupe: size, bounds: bounds)
        #expect(corner.x + size.width <= bounds.maxX && corner.y + size.height <= bounds.maxY)
    }

    @Test("Cropped image encodes to PNG with its pixel size")
    func png() throws {
        let ctx = try #require(CGContext(data: nil, width: 30, height: 12, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(ctx.makeImage())
        let payload = try ScreenCaptureService.payload(png: ScreenCaptureService.png(image))
        #expect(payload.width == 30 && payload.height == 12 && payload.mimeType == "image/png")
    }
}
