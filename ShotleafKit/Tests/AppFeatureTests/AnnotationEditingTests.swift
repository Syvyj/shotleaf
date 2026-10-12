import Testing
import AppKit
@testable import AppFeature

@Suite("Annotation editing")
@MainActor
struct AnnotationEditingTests {
    typealias E = AnnotationEditing

    @Test("Hit: near an arrow's line, inside a box; topmost wins; empty space misses")
    func hit() {
        let arrow = Annotation(kind: .arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0)), color: .coral)
        let box = Annotation(kind: .rectangle(CGRect(x: 40, y: -20, width: 40, height: 40)), color: .coral)
        #expect(E.hit([arrow], at: CGPoint(x: 50, y: 5)) == arrow.id)
        #expect(E.hit([arrow], at: CGPoint(x: 50, y: 30)) == nil)
        #expect(E.hit([arrow, box], at: CGPoint(x: 60, y: 0)) == box.id)
    }

    @Test("Arrow handles move its ends; box corners keep the opposite corner")
    func resize() {
        let arrow: Annotation.Kind = .arrow(from: .zero, to: CGPoint(x: 100, y: 0))
        #expect(E.handle(of: arrow, at: CGPoint(x: 98, y: 2)) == .arrowEnd)
        #expect(E.resized(arrow, .arrowEnd, to: CGPoint(x: 50, y: 50)) == .arrow(from: .zero, to: CGPoint(x: 50, y: 50)))

        let box: Annotation.Kind = .blur(CGRect(x: 10, y: 10, width: 20, height: 20))
        // Drag the bottom-right corner out; top-left stays.
        #expect(E.resized(box, .corner(2), to: CGPoint(x: 50, y: 60)) == .blur(CGRect(x: 10, y: 10, width: 40, height: 50)))
        // Past the opposite corner the box flips instead of going negative.
        #expect(E.resized(box, .corner(2), to: CGPoint(x: 0, y: 0)) == .blur(CGRect(x: 0, y: 0, width: 10, height: 10)))
    }

    @Test("Moving: steps and text move; a cut piece moves but its hole stays")
    func move() {
        let d = CGSize(width: 5, height: -3)
        #expect(E.moved(.step(center: .zero, number: 2), by: d) == .step(center: CGPoint(x: 5, y: -3), number: 2))
        let piece: Annotation.Kind = .piece(source: CGRect(x: 0, y: 0, width: 10, height: 10), offset: .zero, fill: .white)
        #expect(E.moved(piece, by: d) == .piece(source: CGRect(x: 0, y: 0, width: 10, height: 10), offset: d, fill: .white))
        #expect(E.handles(of: piece).isEmpty) // pieces only move
    }

    @Test("Document: add selects; restyle & delete are undoable; undo drops a stale selection")
    func document() {
        let doc = AnnotationDocument()
        let id = doc.add(.arrow(from: .zero, to: CGPoint(x: 10, y: 10)))
        #expect(doc.selection == id)
        doc.restyle(id, color: .sky, lineWidth: 7)
        #expect(doc.selected?.color == .sky && doc.selected?.lineWidth == 7)
        doc.remove(id)
        #expect(doc.isEmpty && doc.selection == nil)
        doc.undo()
        #expect(doc.items.first?.lineWidth == 7)
        doc.undo(); doc.undo()
        #expect(doc.isEmpty)
    }

    @Test("Callout tail: drag it anywhere; drop it on the bubble and it's gone; moving keeps it pointing")
    func calloutTail() {
        let o = CGPoint(x: 100, y: 100)
        let text = Annotation.Kind.text(origin: o, string: "hi", tail: CGPoint(x: 50, y: 200))
        #expect(E.handle(of: text, at: CGPoint(x: 52, y: 198)) == .tail)
        #expect(E.resized(text, .tail, to: CGPoint(x: 300, y: 20)) == .text(origin: o, string: "hi", tail: CGPoint(x: 300, y: 20)))
        let bubble = AnnotationStyle.bubble(origin: o, string: "hi", width: nil, size: AnnotationStyle.fontSize)
        let tailless = E.resized(text, .tail, to: CGPoint(x: bubble.midX, y: bubble.midY))
        #expect(tailless == .text(origin: o, string: "hi", tail: nil))
        // Without a tail there's still a handle on the bubble's edge to pull one out.
        #expect(E.handles(of: tailless).count == 2) // + the width handle
        #expect(E.moved(text, by: CGSize(width: 10, height: 0)) == .text(origin: CGPoint(x: 110, y: 100), string: "hi", tail: CGPoint(x: 50, y: 200)))
    }

    @Test("Callout width: long text wraps by default; the right-edge handle re-wraps it")
    func calloutWidth() {
        let long = String(repeating: "word ", count: 30)
        let o = CGPoint.zero
        let wrapped = AnnotationStyle.bubble(origin: o, string: long, width: nil, size: AnnotationStyle.fontSize)
        #expect(wrapped.width <= AnnotationStyle.textWrap + 20 + 1 && wrapped.height > 60)
        let text = Annotation.Kind.text(origin: o, string: long)
        #expect(E.handle(of: text, at: CGPoint(x: wrapped.maxX, y: wrapped.midY)) == .textWidth)
        let narrow = E.resized(text, .textWidth, to: CGPoint(x: 150, y: 0))
        let b = E.frame(of: narrow)
        #expect(b.width <= 150 + 10 + 1 && b.height > wrapped.height)
        #expect(E.resized(text, .textWidth, to: CGPoint(x: -500, y: 0)) == .text(origin: o, string: long, width: AnnotationStyle.minTextWidth))
    }

    @Test("Bigger callout text makes a bigger bubble")
    func calloutSize() {
        let small = E.frame(of: .text(origin: .zero, string: "hello", size: 14))
        let big = E.frame(of: .text(origin: .zero, string: "hello", size: 36))
        #expect(big.width > small.width * 1.6 && big.height > small.height * 1.6)
    }

    @Test("Ruler: ends snap level/plumb; it selects, moves and re-ends like an arrow")
    func ruler() {
        #expect(E.snapped(.zero, CGPoint(x: 100, y: 4)) == CGPoint(x: 100, y: 0))
        #expect(E.snapped(.zero, CGPoint(x: -3, y: 80)) == CGPoint(x: 0, y: 80))
        #expect(E.snapped(.zero, CGPoint(x: 50, y: 40)) == CGPoint(x: 50, y: 40))
        let ruler = Annotation(kind: .measure(from: .zero, to: CGPoint(x: 100, y: 0)), color: .coral)
        #expect(E.hit([ruler], at: CGPoint(x: 50, y: 3)) == ruler.id)
        #expect(E.resized(ruler.kind, .arrowEnd, to: CGPoint(x: 0, y: 60)) == .measure(from: .zero, to: CGPoint(x: 0, y: 60)))
    }

    @Test("Thicker arrows get bigger heads")
    func arrowHead() {
        #expect(AnnotationStyle.arrowHead(for: 7) > AnnotationStyle.arrowHead(for: 2.5))
    }
}

@Suite("Drag-out")
@MainActor
struct DragOutTests {
    @Test("Select mode: the shot takes the press (drag out); over a mark or with a tool, it passes through")
    func hitTest() {
        let doc = AnnotationDocument()
        doc.add(.rectangle(CGRect(x: 10, y: 10, width: 20, height: 20)))
        doc.selection = nil
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let view = DragOutView.SourceView(frame: parent.bounds)
        view.wantsDrag = { p in doc.tool == nil && AnnotationEditing.hit(doc.items, at: p) == nil }
        parent.addSubview(view)

        #expect(view.hitTest(NSPoint(x: 150, y: 50)) === view) // empty shot → drag out
        #expect(view.hitTest(NSPoint(x: 20, y: 80)) == nil)     // y flips: (20, 20) is on the box
        doc.tool = .arrow
        #expect(view.hitTest(NSPoint(x: 150, y: 50)) == nil)    // a tool draws instead
    }
}

@Suite("Drag payload")
@MainActor
struct DragPayloadTests {
    @Test("Finder gets a file promise it can fulfil; chats get a file URL")
    func promise() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shotleaf-drag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("Shotleaf test.png")
        try Data([1, 2, 3]).write(to: source)

        let promise = ShotPromise(file: source)
        let types = promise.writableTypes(for: NSPasteboard(name: .init("shotleaf.test.drag")))
        #expect(types.contains(.fileURL))
        #expect(types.contains(NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData")) || types.count > 1)
        let name = promise.filePromiseProvider(promise, fileNameForType: "public.png")
        #expect(name == "Shotleaf test.png")

        let target = dir.appendingPathComponent("dropped.png")
        var result: Error?? = .none
        promise.filePromiseProvider(promise, writePromiseTo: target) { result = .some($0) }
        #expect(result != nil && result! == nil)
        #expect(try Data(contentsOf: target) == Data([1, 2, 3]))
    }
}
