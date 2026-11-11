import Foundation

/// Where dragged, pasted and shared files wait for the app that takes them. That app may read
/// a file late, so nothing is removed until the next launch.
enum TempFolder: String, CaseIterable {
    case drag = "Shotleaf Drag", paste = "Shotleaf Paste", share = "Shotleaf Share"

    private var root: URL { FileManager.default.temporaryDirectory.appendingPathComponent(rawValue, isDirectory: true) }

    /// A fresh folder of this kind.
    func new() -> URL {
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func clearAll() {
        for kind in allCases { try? FileManager.default.removeItem(at: kind.root) }
    }
}
