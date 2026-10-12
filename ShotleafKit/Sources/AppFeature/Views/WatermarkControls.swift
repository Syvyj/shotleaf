import SwiftUI
import UniformTypeIdentifiers

/// The watermark's own controls, shared by the screenshot editor and the
/// "Watermark Photos" window: its text or picture, then size, opacity, rotation.
struct WatermarkControls: View {
    @Binding var watermark: Watermark

    var body: some View {
        if watermark.kind == .text {
            TextField("Watermark text", text: $watermark.text)
                .textFieldStyle(.roundedBorder)
        } else {
            Button(watermark.imagePath == nil ? "Choose image…" : "Another image…") {
                Self.chooseImage { watermark.imagePath = $0 }
            }
            .buttonStyle(LeafButtonStyle())
        }
        slider("Size", \.size, Watermark.sizeRange)
        slider("Opacity", \.opacity, Watermark.opacityRange)
        slider("Rotation", \.rotation, Watermark.rotationRange)
    }

    private func slider(_ title: String, _ key: WritableKeyPath<Watermark, CGFloat>, _ range: ClosedRange<CGFloat>) -> some View {
        HStack(spacing: 10) {
            Text(LocalizedStringKey(title)).font(Leaf.font(12, .medium)).opacity(0.7).frame(width: 90, alignment: .leading)
            Slider(value: Binding(get: { watermark[keyPath: key] }, set: { watermark[keyPath: key] = $0 }), in: range).tint(Leaf.leaf)
        }
    }

    /// A logo or any picture; nothing happens if cancelled.
    static func chooseImage(_ picked: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        present(panel) { if let url = $0.first { picked(url.path) } }
    }

    /// An open panel as a sheet on the current window — a free-standing one
    /// would hide behind Shotleaf's floating windows.
    static func present(_ panel: NSOpenPanel, _ picked: @escaping ([URL]) -> Void) {
        NSApp.activate()
        let done: (NSApplication.ModalResponse) -> Void = { if $0 == .OK { picked(panel.urls) } }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: done) } else { done(panel.runModal()) }
    }
}

/// Nine spots, row by row from the top-left; nil selection = placed by hand.
/// Without a title it's just the grid.
struct PositionGrid: View {
    var title: LocalizedStringKey?
    let selection: Int?
    let pick: (Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let title { Text(title).font(Leaf.font(12, .medium)).opacity(0.7).frame(width: 90, alignment: .leading) }
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(0..<3) { row in
                    GridRow {
                        ForEach(0..<3) { column in
                            let spot = row * 3 + column
                            Button { pick(spot) } label: {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(selection == spot ? AnyShapeStyle(Leaf.leaf) : AnyShapeStyle(.primary.opacity(0.1)))
                                    .frame(width: 26, height: 18)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
