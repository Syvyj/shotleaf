import Testing
import Foundation
@testable import Core
@testable import ContextKit

private struct StubClipboard: ClipboardService {
    let text: String?
    func writeText(_ text: String) async throws {}
    func readText() async throws -> String? { self.text }
}
private struct StubSelection: SelectedTextReading {
    let text: String?
    func selectedText(clipboardFallback: Bool) async -> String? { text }
}

@Suite("ContextAggregator")
struct ContextAggregatorTests {
    @Test("Gathers only what requirements ask for")
    func gatesByRequirements() async throws {
        let agg = ContextAggregator(clipboard: StubClipboard(text: "clip"), selection: StubSelection(text: "sel"))

        let none = try await agg.snapshot(requirements: ContextRequirements())
        #expect(none.selectedText == nil)
        #expect(none.clipboardText == nil)

        let both = try await agg.snapshot(requirements: ContextRequirements(needsSelectedText: true, needsClipboard: true))
        #expect(both.selectedText == "sel")
        #expect(both.clipboardText == "clip")
    }

    @Test("primaryText prefers selection over clipboard")
    func primaryText() async throws {
        let agg = ContextAggregator(clipboard: StubClipboard(text: "clip"), selection: StubSelection(text: "sel"))
        let snap = try await agg.snapshot(requirements: ContextRequirements(needsSelectedText: true, needsClipboard: true))
        #expect(snap.primaryText == "sel")
    }
}
