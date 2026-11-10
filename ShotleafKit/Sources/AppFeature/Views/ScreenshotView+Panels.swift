import SwiftUI
import AppKit
import VisionKit
import UniformTypeIdentifiers

/// The editor's flyout panels: the watermark and the background.
extension ScreenshotView {
    // MARK: Watermark

    var watermarkPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: Binding(
                get: { doc.watermark?.kind.rawValue ?? "none" },
                set: { value in
                    if let kind = Watermark.Kind(rawValue: value) {
                        var w = doc.watermark ?? Watermark.saved ?? Watermark()
                        w.kind = kind
                        w.center = nil
                        if kind == .image, w.imagePath == nil {
                            WatermarkControls.chooseImage { w.imagePath = $0; setWatermark(w) }
                        } else {
                            setWatermark(w)
                        }
                    } else {
                        setWatermark(nil)
                    }
                }
            )) {
                Text("None").tag("none")
                Text("Text").tag(Watermark.Kind.text.rawValue)
                Text("Image").tag(Watermark.Kind.image.rawValue)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if let w = doc.watermark {
                PositionGrid(title: "Position", selection: w.center == nil ? w.position : nil) { spot in
                    var n = w; n.position = spot; n.center = nil; setWatermark(n)
                }
                WatermarkControls(watermark: Binding(get: { doc.watermark ?? w }, set: { setWatermark($0) }))
            }
        }
        .frame(width: 300, alignment: .leading)
    }

    func setWatermark(_ w: Watermark?) {
        doc.watermark = w
        if let w { Watermark.saved = w } // the starting point next time it's turned on
    }

    // MARK: Background ("Фон")

    var backdropButton: some View {
        let on = doc.backdrop != nil
        return Button { flyout = flyout == .backdrop ? nil : .backdrop } label: {
            HStack(spacing: 5) {
                Image(systemName: "photo.artframe").font(.system(size: 15, weight: .medium))
                Text("Background").font(Leaf.font(13, .semibold))
                chevron
            }
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(tile(on || flyout == .backdrop))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(on ? Leaf.ink : Color.primary.opacity(0.8))
        .instantTip("Background, padding, corners · remove the background", hidden: flyout == .backdrop)
        .overlay(alignment: .topTrailing) {
            if flyout == .backdrop { flyoutCard { backdropPanel } }
        }
    }

    var backdropPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                backdropSwatch(nil)
                ForEach(Backdrop.gradients.indices, id: \.self) { backdropSwatch(.gradient($0)) }
            }
            HStack(spacing: 6) {
                ForEach(Backdrop.solids.indices, id: \.self) { backdropSwatch(.solid($0)) }
            }
            backdropSlider("Padding", \.padding, Backdrop.paddingRange)
            backdropSlider("Corners", \.corner, Backdrop.cornerRange)
            Divider()
            Button { removeBackground() } label: {
                HStack(spacing: 6) {
                    if removingBackground { ProgressView().controlSize(.small) } else { Image(systemName: "wand.and.stars") }
                    Text("Remove background")
                }
            }
            .buttonStyle(LeafButtonStyle())
            .disabled(removingBackground || doc.base?.cutOut == true)
        }
        .frame(width: 330, alignment: .leading)
    }

    /// nil = no background.
    func backdropSwatch(_ fill: Backdrop.Fill?) -> some View {
        let on = doc.backdrop?.fill == fill
        let solid = if case .solid = fill { true } else { false }
        return Button {
            if let fill {
                var b = doc.backdrop ?? Backdrop()
                b.fill = fill
                doc.backdrop = b
            } else {
                doc.backdrop = nil
            }
        } label: {
            Group {
                if let fill {
                    RoundedRectangle(cornerRadius: solid ? 13 : 7, style: .continuous).fill(Backdrop(fill: fill).style)
                } else {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.primary.opacity(0.06))
                        .overlay(Image(systemName: "nosign").font(.system(size: 12, weight: .semibold)).opacity(0.6))
                }
            }
            .frame(width: solid ? 26 : 36, height: 26)
            .overlay(RoundedRectangle(cornerRadius: solid ? 13 : 7, style: .continuous).strokeBorder(.primary.opacity(0.15), lineWidth: 1))
            .padding(2)
            .overlay(RoundedRectangle(cornerRadius: solid ? 15 : 9, style: .continuous).strokeBorder(on ? Leaf.ink : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    func backdropSlider(_ title: String, _ key: WritableKeyPath<Backdrop, CGFloat>, _ range: ClosedRange<CGFloat>) -> some View {
        HStack(spacing: 10) {
            Text(LocalizedStringKey(title)).font(Leaf.font(12, .medium)).opacity(0.7).frame(width: 70, alignment: .leading)
            Slider(value: Binding(
                get: { (doc.backdrop ?? Backdrop())[keyPath: key] },
                set: { var b = doc.backdrop ?? Backdrop(); b[keyPath: key] = $0; doc.backdrop = b }
            ), in: range)
            .tint(Leaf.leaf)
        }
    }

    /// Keeps the main subject, the rest transparent (on the backdrop, if any).
    func removeBackground() {
        removingBackground = true
        let picture = pictureCG, size = pictureSize
        Task {
            let cut = await Task.detached { BackgroundRemover.cutOut(picture) }.value
            removingBackground = false
            if let cut {
                doc.replacePicture(cut, size: size, cutOut: true)
                flash("Background removed · ⌘Z brings it back")
            } else {
                flash("No subject found to keep")
            }
        }
    }

    // The toolbar shows — and edits — the selected mark's style when there is one.
    var currentColor: AnnotationColor { doc.selected?.color ?? doc.color }
    var currentWidth: CGFloat { doc.selected?.lineWidth ?? doc.lineWidth }

    func setColor(_ color: AnnotationColor) {
        doc.color = color
        if let id = doc.selection { doc.restyle(id, color: color) }
    }

    func setWidth(_ width: CGFloat) {
        doc.lineWidth = width
        if let id = doc.selection { doc.restyle(id, lineWidth: width) }
    }
}
