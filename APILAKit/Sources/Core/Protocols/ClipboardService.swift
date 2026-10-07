import Foundation

/// System clipboard access. Concrete implementation (NSPasteboard) is provided
/// by the Composition Root so executors stay platform-free.
public protocol ClipboardService: Sendable {
    func writeText(_ text: String) async throws
    func readText() async throws -> String?
}
