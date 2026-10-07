import Testing
import AppKit
@testable import ContextKit

@Suite("PasteboardSnapshot")
struct PasteboardSnapshotTests {
    @Test("Restores every type, not just plain text")
    @MainActor
    func restoresAllTypes() {
        let pasteboard = NSPasteboard(name: .init("apila.test.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let png = NSPasteboard.PasteboardType.png
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("hello", forType: .string)
        item.setData(Data([1, 2, 3]), forType: png)
        pasteboard.writeObjects([item])

        let snapshot = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("overwritten", forType: .string)
        snapshot.restore(to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "hello")
        #expect(pasteboard.data(forType: png) == Data([1, 2, 3]))
    }
}
