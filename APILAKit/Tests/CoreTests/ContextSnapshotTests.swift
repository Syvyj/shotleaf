import Testing
import Foundation
@testable import Core

@Suite("ContextSnapshot")
struct ContextSnapshotTests {
    @Test("primaryText prefers selection, falls back to clipboard")
    func primaryText() {
        let withSelection = ContextSnapshot(selectedText: "sel", clipboardText: "clip", capturedAt: Date())
        #expect(withSelection.primaryText == "sel")

        let clipboardOnly = ContextSnapshot(clipboardText: "clip", capturedAt: Date())
        #expect(clipboardOnly.primaryText == "clip")
    }

    @Test("withRecognizedScreenText returns an immutable copy")
    func immutableEnrichment() {
        let original = ContextSnapshot(selectedText: "hi", capturedAt: Date())
        let enriched = original.withRecognizedScreenText("ocr")

        #expect(original.recognizedScreenText == nil)
        #expect(enriched.recognizedScreenText == "ocr")
        #expect(enriched.selectedText == "hi")
    }
}
