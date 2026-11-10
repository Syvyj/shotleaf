import AppKit
import SwiftUI

/// The emoji picker under the cursor, in the Leaves style: "1 👍  2 😂 …";
/// the first one (what Tab takes) is highlighted, a click picks too. Never
/// takes the keyboard — the user keeps typing in their app.
@MainActor
final class EmojiPickerPanel: NSPanel {
    private let onPick: (Int) -> Void

    init(onPick: @escaping (Int) -> Void) {
        self.onPick = onPick
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows the candidates under `caret` (AppKit screen coordinates) and
    /// returns the panel's frame.
    func show(_ candidates: [EmojiShortcodes.Candidate], under caret: CGRect) -> CGRect {
        let host = FirstClickHostingView(rootView: EmojiPickerRow(candidates: candidates, onPick: onPick))
        contentView = host
        let size = host.fittingSize
        let frame = CGRect(x: caret.minX - 8, y: caret.minY - size.height - 6, width: size.width, height: size.height)
        setFrame(frame, display: true)
        orderFrontRegardless()
        return frame
    }
}

/// A click on the picker counts even though its window never becomes key.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct EmojiPickerRow: View {
    let candidates: [EmojiShortcodes.Candidate]
    let onPick: (Int) -> Void
    @State private var hovered: Int?
    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(candidates.enumerated()), id: \.offset) { i, candidate in
                Button { onPick(i) } label: {
                    HStack(spacing: 3) {
                        Text(verbatim: "\(i + 1)")
                            .font(Leaf.font(10, .bold))
                            .foregroundStyle(Leaf.ink)
                        Text(verbatim: candidate.emoji).font(.system(size: 19))
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background {
                        let on = hovered.map { $0 == i } ?? (i == 0) // Tab takes the first
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(on ? AnyShapeStyle(Leaf.selection) : AnyShapeStyle(.clear))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? i : (hovered == i ? nil : hovered) }
                .help(candidate.name.replacingOccurrences(of: "_", with: " "))
            }
        }
        .padding(5)
        .background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Leaf.surface)
                shape.fill(LinearGradient(colors: [Leaf.fresh.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom))
            }
        }
        .overlay(shape.strokeBorder(Leaf.markGradient, lineWidth: 1).opacity(0.55))
        .clipShape(shape)
        .fixedSize()
    }
}
