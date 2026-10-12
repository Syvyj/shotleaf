import Testing
import AppKit
@testable import AppFeature

@Suite("Snippets")
@MainActor
struct SnippetTests {
    @Test("Pictures: saved with the snippet, pasted as separate pictures after the text, dropped from disk when unused")
    func pictures() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shotleaf-snip-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SnippetStore(file: dir.appendingPathComponent("s.json"))
        let work = SnippetFolder(name: "Робота")
        store.folders = [work]
        let png = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!.representation(using: .png, properties: [:])!
        let saved = store.save(title: "Схема", text: "Як доїхати:", pngs: [png, png], folder: work.id)
        #expect(saved.folder == work.id && saved.images?.count == 2)
        #expect(store.imageURLs(saved).allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(SnippetStore(file: store.file).snippets.first?.images == saved.images) // survives a restart

        let board = NSPasteboard(name: .init("shotleaf-test-\(UUID())"))
        defer { board.releaseGlobally() }
        Paster.put("Як доїхати:", images: store.imageURLs(saved), on: board)
        let items = board.pasteboardItems ?? []
        #expect(items.count == 3 && items[0].string(forType: .string) == "Як доїхати:" && items[1].data(forType: .png) != nil)

        let files = store.imageURLs(saved)
        store.snippets.removeAll()
        #expect(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test("Variables: date, time, clipboard, answers; {cursor} says how far back the caret goes")
    func expand() {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 14; c.hour = 9; c.minute = 5
        let now = Calendar.current.date(from: c)!
        let text = "Добрий день, {?Ім'я}! Рахунок до {date}.{cursor} З повагою"
        #expect(SnippetText.questions(in: text + " {?Ім'я} {?Сума}") == ["Ім'я", "Сума"])
        let out = SnippetText.expand(text, answers: ["Ім'я": "Марино"], now: now)
        #expect(out.text.hasPrefix("Добрий день, Марино! Рахунок до "))
        #expect(out.text.hasSuffix(". З повагою") && out.afterCursor == " З повагою".count)
        #expect(SnippetText.expand("{clipboard}!", clipboard: "abc").text == "abc!")
        #expect(SnippetText.expand("a{?x}b").text == "ab")                      // unanswered: empty
        #expect(SnippetText.expand("x{cursor}y{cursor}z") == ("xyz", 2))       // only the first counts
    }

    @Test("An abbreviation that starts with a letter fires only as a whole word")
    func wholeWord() {
        let mail = [Snippet(title: "Mail", text: "me@example.com", abbreviation: "mail")]
        #expect(SnippetExpander.match("mail", in: mail) != nil)
        #expect(SnippetExpander.match("write to mail", in: mail) != nil)
        #expect(SnippetExpander.match(";mail", in: mail) != nil)
        #expect(SnippetExpander.match("gmail", in: mail) == nil)
        #expect(SnippetExpander.match("xx;addr", in: [Snippet(title: "A", text: "a", abbreviation: ";addr")]) != nil)
    }

    @Test("Abbreviation: the typing must end with it; the longest wins")
    func match() {
        let s = [Snippet(title: "a", text: "A", abbreviation: ";addr"), Snippet(title: "b", text: "B", abbreviation: "dr"),
                 Snippet(title: "c", text: "C")]
        #expect(SnippetExpander.match("hello ;addr", in: s)?.title == "a")
        #expect(SnippetExpander.match("hello ;add", in: s) == nil)
        #expect(SnippetExpander.match("word dr", in: s)?.title == "b")
    }

    @Test("Store: search by title, text or abbreviation; survives a restart")
    func store() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("shotleaf-snippets-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = SnippetStore(file: file)
        let folder = SnippetFolder(name: "Робота")
        store.folders.append(folder)
        store.snippets.append(Snippet(title: "Реквізити ФОП", text: "IBAN UA00 1234 5678 0000 0000 0000 001", abbreviation: ";рекв", folder: folder.id))
        store.snippets.append(Snippet(title: "Підпис", text: "З повагою, Олексій", abbreviation: ";підп"))
        #expect(store.search("iban").count == 1 && store.search(";підп").count == 1 && store.search("").count == 2)
        let again = SnippetStore(file: file)
        #expect(again.snippets.count == 2 && again.folder(again.snippets[0].folder)?.name == "Робота")
    }

    @Test("A temporary paste puts the clipboard back as it was")
    func restore() {
        let board = NSPasteboard(name: .init("shotleaf-test-\(UUID())"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("мій текст", forType: .string)
        board.setData("{\\rtf1 x}".data(using: .utf8)!, forType: .rtf)
        let saved = Paster.snapshot(board)
        Paster.put("сніпет", on: board)
        #expect(board.string(forType: .string) == "сніпет")
        Paster.restore(saved, to: board)
        #expect(board.string(forType: .string) == "мій текст" && board.data(forType: .rtf) != nil)
        #expect(board.types?.contains(ClipboardHistory.ownType) == true) // not recorded again
    }

    @Test("Editor and the panel's Snippets tab render")
    func render() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shotleaf-snip-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SnippetStore(file: dir.appendingPathComponent("s.json"))
        let work = SnippetFolder(name: "Робота", color: 0)
        store.folders = [work, SnippetFolder(name: "Підписи", color: 1), SnippetFolder(name: "Адреси", color: 2)]
        store.snippets = [
            Snippet(title: "Відповідь клієнту", text: "Добрий день, {?Ім'я}!\nДякую за звернення. Надішлю рахунок до {date}.\n{cursor}\nЗ повагою, Олексій", abbreviation: ";відп", folder: work.id),
            Snippet(title: "Реквізити ФОП", text: "IBAN UA00 1234 5678 0000 0000 0000 001", abbreviation: ";рекв", folder: work.id),
        ]
        try renderPreview(SnippetEditorView(store: store).frame(width: 1000, height: 600), "snippets-editor.png")
        let model = ClipboardPanelModel(history: ClipboardHistory(folder: dir), snippets: store)
        model.showsSnippets = true
        try renderPreview(ClipboardPanelView(model: model, pick: { _, _ in }, close: {}), "clipboard-snippets.png")
        model.asking = store.snippets[0]
        model.answers = ["Ім'я": "Марино"]
        try renderPreview(ClipboardPanelView(model: model, pick: { _, _ in }, close: {}), "clipboard-asking.png")
    }
}
