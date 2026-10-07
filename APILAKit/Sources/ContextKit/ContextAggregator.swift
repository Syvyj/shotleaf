import Core
import Foundation

/// Gathers the requested context into a `ContextSnapshot`. This iteration wires
/// selected text (AX + ⌘C fallback) and clipboard; active app / browser URL /
/// screen image land in later iterations. Privacy-first: gathers only what the
/// action's `ContextRequirements` ask for.
public struct ContextAggregator: ContextProviding {
    private let clipboard: any ClipboardService
    private let selection: any SelectedTextReading

    public init(
        clipboard: any ClipboardService = SystemClipboard(),
        selection: any SelectedTextReading = AXSelectedTextReader()
    ) {
        self.clipboard = clipboard
        self.selection = selection
    }

    public func snapshot(requirements: ContextRequirements) async throws -> ContextSnapshot {
        var clipboardText: String?
        if requirements.needsClipboard {
            clipboardText = try? await clipboard.readText()
        }

        var selectedText: String?
        if requirements.needsSelectedText {
            selectedText = await selection.selectedText(clipboardFallback: true)
        }

        return ContextSnapshot(
            selectedText: selectedText,
            clipboardText: clipboardText,
            capturedAt: Date()
        )
    }
}
