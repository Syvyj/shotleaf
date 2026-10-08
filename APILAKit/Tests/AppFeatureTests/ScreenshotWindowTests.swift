import Testing
import SwiftUI
@testable import Core
@testable import ActionKit
@testable import PerceptionKit
@testable import AppFeature

@Suite("Screenshot window")
@MainActor
struct ScreenshotWindowTests {
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
        let noop = ScreenshotActions(copy: {}, save: { nil }, pin: {}, text: {}, ask: {}, close: {})
        let host = NSHostingView(rootView: ScreenshotView(
            image: NSImage(size: display), pixelSize: CGSize(width: 680, height: 1560),
            fileURL: URL(fileURLWithPath: "/tmp/x.png"), displaySize: display, actions: noop))
        let extra = host.fittingSize.height - display.height
        #expect(extra > 0 && extra <= ScreenshotWindows.chromeHeight, "chrome is \(extra) pt")
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

    @Test("Text from the screenshot window runs OCR in the panel")
    func textHandOff() async throws {
        let vm = PanelViewModel(
            runner: ActionRunner(context: ShotContext(), executors: [.ocr: OCRExecutor(recognizer: ShotOCR())]),
            inserter: ResultInserter(clipboard: ShotClipboard()),
            actions: [],
            accessibilityGranted: { false }
        )
        vm.present(snapshot: ContextSnapshot(capturedAt: Date()), sourceApp: nil)
        vm.useScreenshot(ImagePayload(data: Data([0]), width: 1, height: 1), ask: false)
        for _ in 0..<200 where vm.screen != .result { try await Task.sleep(for: .milliseconds(5)) }
        #expect(vm.output == "hello from the shot")
    }

    @Test("Renders (design preview when APILA_PREVIEW_DIR is set)")
    func render() throws {
        let image = NSImage(size: NSSize(width: 640, height: 360), flipped: false) { r in
            NSGradient(starting: .systemTeal, ending: .systemIndigo)!.draw(in: r, angle: 30)
            ("Shottr-level APILA" as NSString).draw(at: NSPoint(x: 40, y: 160), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 40), .foregroundColor: NSColor.white])
            return true
        }
        let noop = ScreenshotActions(copy: {}, save: { nil }, pin: {}, text: {}, ask: {}, close: {})
        let view = ScreenshotView(image: image, pixelSize: CGSize(width: 1280, height: 720), fileURL: URL(fileURLWithPath: "/tmp/x.png"),
                                  displaySize: CGSize(width: 640, height: 360), actions: noop)
        try renderPreview(view, "screenshot-window.png")
        try renderPreview(view, "screenshot-window-dark.png", dark: true)
    }
}

private struct ShotContext: ContextProviding {
    func snapshot(requirements: ContextRequirements) async throws -> ContextSnapshot { ContextSnapshot(capturedAt: Date()) }
}
private struct ShotOCR: TextRecognizing {
    func recognizeText(in image: ImagePayload) async throws -> String { "hello from the shot" }
}
private struct ShotClipboard: ClipboardService {
    func writeText(_ text: String) async throws {}
    func readText() async throws -> String? { nil }
}
