import Testing
import AppKit
@testable import AppFeature

@Suite("Clipboard history")
@MainActor
struct ClipboardHistoryTests {
    static func temp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("shotleaf-clip-\(UUID())") }

    @Test("Kinds: links, colours, text; card numbers and tokens are sensitive")
    func kinds() {
        #expect(ClipboardHistory.kind(of: "https://jac.black/") == .link)
        #expect(ClipboardHistory.kind(of: "#8FBF3A") == .color && ClipboardHistory.kind(of: "8fbf3a") == .color)
        #expect(ClipboardHistory.kind(of: "see https://x.com") == .text)
        #expect(ClipboardHistory.looksSensitive("4111 1111 1111 1111"))
        #expect(!ClipboardHistory.looksSensitive("4111 1111 1111 1112"))   // fails Luhn
        #expect(ClipboardHistory.looksSensitive("ghp_a1b2c3"))
        #expect(ClipboardHistory.looksSensitive("a8F3kq92LmZ0pXr7Tq1vB6nW4yH2cE5j"))
        #expect(!ClipboardHistory.looksSensitive("Project ID: alpha-1234"))
    }

    @Test("Reads text, files and images off a pasteboard; skips nothing-to-keep")
    func read() throws {
        let board = NSPasteboard(name: .init("shotleaf-test-\(UUID())"))
        defer { board.releaseGlobally() }
        board.clearContents(); board.setString("привіт", forType: .string)
        #expect(ClipboardHistory.read(board)?.0.text == "привіт")
        board.clearContents(); board.writeObjects([URL(fileURLWithPath: "/tmp/a.pdf") as NSURL])
        #expect(ClipboardHistory.read(board)?.0.kind == .file)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        board.clearContents(); board.setData(rep.tiffRepresentation!, forType: .tiff)
        let (image, png) = try #require(ClipboardHistory.read(board))
        #expect(image.kind == .image && image.imageSize == CGSize(width: 8, height: 4) && png != nil)
        board.clearContents(); board.setString("   ", forType: .string)
        #expect(ClipboardHistory.read(board) == nil)
    }

    @Test("A screenshot is kept without copying, its edit replaces it, and several paste as separate pictures")
    func screenshotsTogether() throws {
        let folder = Self.temp()
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = ClipboardHistory(folder: folder)
        let png = { (w: Int) in
            NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!.representation(using: .png, properties: [:])!
        }
        let first = try #require(history.addScreenshot(png(8)))
        history.addScreenshot(png(10))
        history.updateImage(first, png: png(12))
        let shot = try #require(history.items.first { $0.id == first })
        #expect(shot.screenshot == true && shot.imageSize == CGSize(width: 12, height: 4) && history.items.count == 2)

        history.add(ClipItem(kind: .text, text: "see below"))
        let board = NSPasteboard(name: .init("shotleaf-test-\(UUID())"))
        defer { board.releaseGlobally() }
        history.copyTogether(history.items, to: board)
        let items = board.pasteboardItems ?? []
        #expect(items.count == 3) // the text, then each picture on its own
        #expect(items.first?.string(forType: .string) == "see below")
        #expect(items.dropFirst().allSatisfy { $0.data(forType: .png) != nil && $0.string(forType: .fileURL) != nil })
        #expect(items.allSatisfy { $0.types.contains(ClipboardHistory.ownType) })
    }

    @Test("Same text moves up, pins come first, search matches every word and image text, survives a restart")
    func history() {
        let dir = Self.temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let h = ClipboardHistory(folder: dir)
        h.add(ClipItem(kind: .text, text: "перший рядок"))
        h.add(ClipItem(kind: .link, text: "https://multiplex.ua/imax"))
        var shot = ClipItem(kind: .image, text: "")
        shot.imageText = "IMAX субота 19:00"
        h.add(shot)
        h.add(ClipItem(kind: .text, text: "перший рядок")) // again
        #expect(h.items.count == 3 && h.items.first?.text == "перший рядок")
        h.togglePin(h.items[2].id)
        #expect(h.search("").first?.pinned == true)
        #expect(h.search("imax").count == 2)
        #expect(h.search("imax субота").count == 1)
        #expect(h.search("", kind: .link).count == 1)
        #expect(ClipboardHistory(folder: dir).items.count == 3)
        h.clear()
        #expect(h.items.count == 1 && h.items[0].pinned)
    }

    @Test("Copy back marks it as Shotleaf's, plain drops the formatting")
    func copyBack() {
        let dir = Self.temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let board = NSPasteboard(name: .init("shotleaf-test-\(UUID())"))
        defer { board.releaseGlobally() }
        let h = ClipboardHistory(folder: dir)
        var item = ClipItem(kind: .text, text: "bold")
        item.rtf = "{\\rtf1 \\b bold}".data(using: .utf8)
        h.add(item)
        h.copy(h.items[0], to: board)
        #expect(board.types?.contains(ClipboardHistory.ownType) == true && board.data(forType: .rtf) != nil)
        h.copy(h.items[0], plain: true, to: board)
        #expect(board.data(forType: .rtf) == nil && board.string(forType: .string) == "bold")
    }

    @Test("Panel renders")
    func panel() throws {
        let dir = Self.temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let h = ClipboardHistory(folder: dir)
        h.add(ClipItem(kind: .text, text: "вул. Хрещатик, 22, кв. 14"))
        h.add(ClipItem(kind: .color, text: "#8FBF3A"))
        h.add(ClipItem(kind: .link, text: "https://multiplex.ua/imax/schedule"))
        h.add(ClipItem(kind: .text, text: "о, IMAX я б прям пішов у суботу, якщо будуть квитки на вечір"))
        h.togglePin(h.items[3].id)
        let model = ClipboardPanelModel(history: h, snippets: SnippetStore(file: dir.appendingPathComponent("s.json")))
        model.query = "imax"
        try renderPreview(ClipboardPanelView(model: model, pick: { _, _ in }, close: {}), "clipboard-panel.png")
        model.query = ""
        try renderPreview(ClipboardPanelView(model: model, pick: { _, _ in }, close: {}), "clipboard-panel-all.png", dark: true)
    }
}

@Suite("Clipboard actions and picking several")
@MainActor
struct ClipActionTests {
    @Test("Clean links, one line, trim, JSON; only actions that change something are offered")
    func actions() {
        #expect(ClipAction.cleanLinks("see https://shop.ua/item?id=7&utm_source=fb&fbclid=XYZ now") == "see https://shop.ua/item?id=7 now")
        #expect(ClipAction.cleanLinks("https://a.com/?utm_medium=x") == "https://a.com/")
        #expect(ClipAction.cleanLinks("https://a.com/?q=1") == "https://a.com/?q=1")
        #expect(ClipAction.oneLine.apply("один\n  два\n\nтри") == "один два три")
        #expect(ClipAction.trim.apply("  a    b \n c  ") == "a b\nc")
        #expect(ClipAction.formatJSON.apply(#"{"b":1,"a":[1,2]}"#)?.hasPrefix("{\n  \"a\"") == true)
        #expect(ClipAction.formatJSON.apply("not json") == nil)
        let offered = ClipAction.available(for: "hello")
        #expect(offered.contains(.uppercase) && !offered.contains(.lowercase) && !offered.contains(.formatJSON) && offered.contains(.saveSnippet))
    }

    @Test("⇧↓ picks the current and the next; ⌘-click toggles; the order is kept; renders")
    func marking() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shotleaf-mark-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let h = ClipboardHistory(folder: dir)
        for text in ["вул. Хрещатик, 22", "+380 67 123 45 67", "Олексій Зюзін", "https://shop.ua/item?id=7&utm_source=fb"] {
            h.add(ClipItem(kind: ClipboardHistory.kind(of: text), text: text))
        }
        let model = ClipboardPanelModel(history: h, snippets: SnippetStore(file: dir.appendingPathComponent("s.json")))
        model.extendMark(1)
        #expect(model.marked.count == 2 && model.selected == 1)
        model.toggleMark(h.items[3].id)
        #expect(model.markedItems.map(\.text) == [h.items[0].text, h.items[1].text, h.items[3].text])
        try renderPreview(ClipboardPanelView(model: model, pick: { _, _ in }, close: {}), "clipboard-marked.png")
        model.marked = []
        model.selected = 0
        model.actionsShown = true
        try renderPreview(ClipboardPanelView(model: model, pick: { _, _ in }, close: {}), "clipboard-actions.png")
    }
}
