import SwiftUI
import AppKit

/// Renders a SwiftUI view through a real NSHostingView (so AppKit-backed pieces
/// like the drag handle draw too) at its own ideal size, on a backdrop, into
/// SHOTLEAF_PREVIEW_DIR/<name> — only when that env var is set.
@MainActor
func renderPreview<V: View>(_ view: V, _ name: String, dark: Bool = false) throws {
    guard let dir = ProcessInfo.processInfo.environment["SHOTLEAF_PREVIEW_DIR"] else { return }
    let framed = view.fixedSize().padding(40)
        .background(dark ? Color(white: 0.16) : Color(white: 0.88))
        .environment(\.colorScheme, dark ? .dark : .light)
    let host = NSHostingView(rootView: framed)
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.frame = CGRect(origin: .zero, size: host.fittingSize)
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
}
