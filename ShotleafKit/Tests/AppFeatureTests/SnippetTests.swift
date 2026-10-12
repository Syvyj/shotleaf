import Testing
import AppKit
@testable import AppFeature

@Suite("Snippets")
@MainActor
struct SnippetTests {
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
        store.snippets.append(Snippet(title: "Підпис", text: "З повагою, Оксана", abbreviation: ";підп"))
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
            Snippet(title: "Відповідь клієнту", text: "Добрий день, {?Ім'я}!\nДякую за звернення. Надішлю рахунок до {date}.\n{cursor}\nЗ повагою, Оксана", abbreviation: ";відп", folder: work.id),
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
