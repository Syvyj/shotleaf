import SwiftUI

/// Text read off a screenshot: editable, so a word the OCR got wrong can be
/// fixed before copying. ⌘C copies it all and closes, as in the screenshot
/// editor; with some text selected it copies just that and stays. esc closes.
struct TextResultView: View {
    @State var text: String
    let title: LocalizedStringKey
    let copy: (String) -> Void
    let close: () -> Void
    @State private var copied = false
    @State private var selection: TextSelection?

    /// The selected text, if any (a stale range after an edit counts as none).
    private var selected: String? {
        guard case .selection(let range)? = selection?.indices, !range.isEmpty,
              range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex else { return nil }
        return String(text[range])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                BrandLogo()
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(Leaf.font(15, .semibold))
                    Text("\(text.count) characters").font(Leaf.font(11)).opacity(0.5)
                }
                Spacer()
                if copied {
                    Text("Copied").font(Leaf.font(12, .semibold)).foregroundStyle(Leaf.ink).transition(.opacity)
                }
            }
            .overlay(WindowDragArea())

            TextEditor(text: $text, selection: $selection)
                .font(Leaf.font(14))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Leaf.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    if text.isEmpty {
                        Text("No text found").font(Leaf.font(13)).foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 160, maxHeight: .infinity)

            HStack(spacing: 6) {
                Button {
                    if let selected {
                        copy(selected)
                        withAnimation { copied = true }
                    } else {
                        copy(text)
                        close()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(selected == nil ? "Copy all" : "Copy selection")
                        Text(verbatim: "⌘C").font(Leaf.font(10.5, .semibold)).opacity(0.5)
                    }
                }
                .buttonStyle(LeafButtonStyle(prominent: true))
                .keyboardShortcut("c", modifiers: .command)
                .disabled(text.isEmpty)
                Spacer()
                Button {
                    close()
                } label: {
                    HStack(spacing: 5) {
                        Text("Close")
                        Text(verbatim: "esc").font(Leaf.font(10.5, .semibold)).opacity(0.5)
                    }
                }
                .buttonStyle(LeafButtonStyle())
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(minWidth: 460, maxWidth: .infinity, minHeight: 280, maxHeight: .infinity, alignment: .topLeading)
        .leafPanelChrome()
        .overlay(alignment: .bottomTrailing) { WindowResizeGrip().frame(width: 12, height: 12).padding(2) }
        .overlay(WindowEdgeResizer())
    }
}
