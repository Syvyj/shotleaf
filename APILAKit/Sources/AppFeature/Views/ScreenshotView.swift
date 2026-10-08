import SwiftUI
import AppKit

/// What the screenshot window can do; wired by `ScreenshotWindows`.
struct ScreenshotActions {
    var copy: () -> Void
    var save: () -> URL?
    var pin: () -> Void
    var text: () -> Void
    var ask: () -> Void
    var close: () -> Void
}

/// Shottr-style preview after a capture: the image (drag it into any app) and
/// the actions, in the "Leaves" style. Keyboard: ↩/⌘C copy, ⌘S save, P pin,
/// T text, A ask, esc close.
struct ScreenshotView: View {
    let image: NSImage
    let pixelSize: CGSize
    /// The PNG on disk — what drag-and-drop hands to other apps.
    let fileURL: URL
    let displaySize: CGSize
    let actions: ScreenshotActions

    @State private var toast: String?

    /// Wide enough for the toolbar and the hint line.
    static let minContentWidth: CGFloat = 520

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: displaySize.width, height: displaySize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.12)))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .onDrag { NSItemProvider(contentsOf: fileURL) ?? NSItemProvider() }
                .help("Drag into any app")
            toolbar
            HintBar(items: [("↩", "copy & close"), ("⌘S", "save"), ("P", "pin"), ("T", "text"), ("A", "ask"), ("esc", "close")])
        }
        // A fixed width: the toolbar's Spacer would otherwise ask for "infinite"
        // width and the window would be sized/centred from that.
        .frame(width: max(displaySize.width, Self.minContentWidth), alignment: .leading)
        .padding(14)
        .leafPanelChrome()
    }

    private var header: some View {
        HStack(spacing: 8) {
            BrandLogo()
            Text("Screenshot").font(Leaf.font(16, .semibold))
            Text(verbatim: "\(Int(pixelSize.width)) × \(Int(pixelSize.height))") // no locale grouping
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(.primary.opacity(0.06), in: Capsule())
            Spacer()
            if let toast {
                Text(toast)
                    .font(Leaf.font(12, .semibold))
                    .foregroundStyle(Leaf.ink)
                    .transition(.opacity)
            }
        }
        .overlay(WindowDragArea())
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            Button("Copy") { actions.copy(); flash("Copied") }
                .buttonStyle(LeafButtonStyle(prominent: true))
                .keyboardShortcut("c", modifiers: .command)
            Button("Save") {
                if let url = actions.save() { flash("Saved to \(url.deletingLastPathComponent().lastPathComponent)") }
            }
            .buttonStyle(LeafButtonStyle())
            .keyboardShortcut("s", modifiers: .command)
            Button("Pin") { actions.pin() }
                .buttonStyle(LeafButtonStyle())
                .keyboardShortcut("p", modifiers: [])
            Button("Text") { actions.text() }
                .buttonStyle(LeafButtonStyle())
                .keyboardShortcut("t", modifiers: [])
            Button("Ask AI") { actions.ask() }
                .buttonStyle(LeafButtonStyle())
                .keyboardShortcut("a", modifiers: [])
            Spacer()
            Button("Close") { actions.close() }
                .buttonStyle(LeafButtonStyle())
                .keyboardShortcut(.cancelAction)
            // ↩ = the most common thing: copy and get out of the way.
            Button("") { actions.copy(); actions.close() }
                .keyboardShortcut(.defaultAction)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { if toast == text { toast = nil } }
        }
    }
}

/// A screenshot pinned above all windows: just the image. Drag to move,
/// esc or the × (on hover) to close, ⌘C to copy.
struct PinnedScreenshotView: View {
    let image: NSImage
    let size: CGSize
    let copy: () -> Void
    let close: () -> Void
    @State private var hovered = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Leaf.accent, lineWidth: hovered ? 2 : 0))
            .overlay(WindowDragArea())
            .overlay(alignment: .topTrailing) {
                if hovered {
                    Button(action: close) {
                        Text("×").font(Leaf.font(15, .bold)).frame(width: 24, height: 24)
                    }
                    .buttonStyle(LeafButtonStyle())
                    .padding(6)
                }
            }
            .onHover { hovered = $0 }
            .background {
                Button("") { close() }.keyboardShortcut(.cancelAction).opacity(0)
                Button("") { copy() }.keyboardShortcut("c", modifiers: .command).opacity(0)
            }
    }
}
