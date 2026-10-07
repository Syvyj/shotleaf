import Core
import AppKit

/// NSPasteboard-backed clipboard. Canonical `ClipboardService` implementation —
/// used both as a context source (read) and by the clipboard executor (write).
public struct SystemClipboard: ClipboardService {
    public init() {}

    public func writeText(_ text: String) async throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    public func readText() async throws -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}
