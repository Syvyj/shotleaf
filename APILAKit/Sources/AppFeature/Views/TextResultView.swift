import SwiftUI

/// Text read off a screenshot: editable, so a word the OCR got wrong can be
/// fixed before copying. ⌘↩ copies it all and closes, esc closes; ⌘C copies
/// just the selection, as in any text field.
struct TextResultView: View {
    @State var text: String
    let title: LocalizedStringKey
    let copy: (String) -> Void
    let close: () -> Void
    @State private var copied = false

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

            TextEditor(text: $text)
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
                    copy(text)
                    withAnimation { copied = true }
                    close()
                } label: {
                    HStack(spacing: 5) {
                        Text("Copy all")
                        Text(verbatim: "⌘↩").font(Leaf.font(10.5, .semibold)).opacity(0.5)
                    }
                }
                .buttonStyle(LeafButtonStyle(prominent: true))
                .keyboardShortcut(.return, modifiers: .command)
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
        .overlay(alignment: .bottomTrailing) { WindowResizeGrip().frame(width: 18, height: 18).padding(4) }
        .overlay(WindowEdgeResizer())
    }
}
