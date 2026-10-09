import Testing
import AppKit
@testable import Core
@testable import PerceptionKit
@testable import CaptureKit

/// Renders text into a PNG, like a real screenshot of a text field.
private func pngWithText(_ text: String) throws -> Data {
    let size = NSSize(width: 900, height: 160)
    let image = NSImage(size: size, flipped: false) { rect in
        NSColor.white.setFill()
        rect.fill()
        (text as NSString).draw(at: NSPoint(x: 30, y: 50), withAttributes: [
            .font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black,
        ])
        return true
    }
    let tiff = try #require(image.tiffRepresentation)
    return try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
}

@Suite("OCR")
struct OCRTests {
    @Test("Vision reads Latin and Ukrainian text from an image")
    func recognizes() async throws {
        let payload = try ScreenCaptureService.payload(png: pngWithText("Hello APILA Привіт світ"))
        #expect(payload.width > 0 && payload.height > 0)
        let text = try await VisionTextRecognizer().recognizeText(in: payload)
        #expect(text.contains("Hello"))
        #expect(text.contains("APILA"))
        #expect(text.lowercased().contains("привіт"))
    }

    @Test("An image without text gives empty text")
    func emptyImage() async throws {
        let payload = try ScreenCaptureService.payload(png: pngWithText(""))
        #expect(try await VisionTextRecognizer().recognizeText(in: payload).isEmpty)
    }
}
