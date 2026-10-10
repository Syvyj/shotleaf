import SwiftUI
import ImageIO

/// "Watermark Photos": drop photos, set the mark once, look through them and
/// move it on the ones where it's in the way (a grid spot or by hand).
/// Same look as the screenshot window: leaf chrome, name on top, the photo on
/// a canvas, settings beside it, actions in one row at the bottom.
struct BatchWatermarkView: View {
    @Bindable var model: BatchWatermark
    var close: () -> Void = {}
    @State private var preview: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 10) {
                    if model.photos.isEmpty { dropZone } else {
                        previewArea
                        thumbnails
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.035)))
                sidebar
                    .padding(14)
                    .frame(width: 300)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.035)))
            }
            actionRow.zIndex(1)
        }
        .padding(14)
        .frame(minWidth: 980, maxWidth: .infinity, minHeight: 680, maxHeight: .infinity)
        .leafPanelChrome()
        .overlay(alignment: .bottomTrailing) { WindowResizeGrip().frame(width: 12, height: 12).padding(2) }
        .overlay(WindowEdgeResizer())
        .dropDestination(for: URL.self) { urls, _ in model.add(urls); return true }
        .task(id: model.selected) {
            preview = nil
            if let url = model.selected { preview = await Self.loadPreview(url) }
        }
    }

    // MARK: Header & actions

    private var header: some View {
        HStack(spacing: 8) {
            BrandLogo()
            Text("Watermark Photos").font(Leaf.font(15, .semibold)).fixedSize() // the count is on the Apply button
            Spacer()
        }
        .overlay(WindowDragArea())
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            if let progress = model.progress {
                ProgressView(value: progress).tint(Leaf.leaf).frame(width: 220)
            } else {
                Button { Task { await model.apply() } } label: {
                    HStack(spacing: 5) {
                        Text("Apply to \(model.photos.count) photos")
                        Text(verbatim: "⌘↩").font(Leaf.font(10.5, .semibold)).opacity(0.5)
                    }
                }
                .buttonStyle(LeafButtonStyle(prominent: true))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.photos.isEmpty || (model.watermark.kind == .image && model.watermark.imagePath == nil))
            }
            Button("Add photos") { choosePhotos() }.buttonStyle(LeafButtonStyle())
            if let result = model.result {
                Text(result).font(Leaf.font(12, .medium)).foregroundStyle(Leaf.ink).lineLimit(1).padding(.leading, 6)
            }
            Spacer(minLength: 6)
            Button(action: close) {
                HStack(spacing: 5) {
                    Text("Close")
                    Text(verbatim: "esc").font(Leaf.font(10.5, .semibold)).opacity(0.5)
                }
            }
            .buttonStyle(LeafButtonStyle())
            .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: Photos

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.stack").font(.system(size: 44, weight: .light)).foregroundStyle(Leaf.ink)
            Text("Drop photos here").font(Leaf.font(18, .semibold))
            Button("Choose photos…") { choosePhotos() }.buttonStyle(LeafButtonStyle(prominent: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Leaf.ink.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
    }

    /// The selected photo with its mark; drag anywhere to place the mark by hand (this photo only).
    private var previewArea: some View {
        GeometryReader { geo in
            if let preview, let url = model.selected {
                let fit = Self.fit(CGSize(width: preview.width, height: preview.height), in: geo.size)
                let mark = model.mark(for: url)
                ZStack {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .interpolation(.high)
                    Canvas { context, size in
                        context.withCGContext { mark.draw(in: $0, area: CGRect(origin: .zero, size: size)) }
                    }
                    .allowsHitTesting(false)
                }
                .frame(width: fit.width, height: fit.height)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let c = CGPoint(x: min(max(value.location.x / fit.width, 0), 1), y: min(max(value.location.y / fit.height, 0), 1))
                    model.overrides[url] = .init(position: mark.position, center: c)
                })
                .onHover { inside in (inside ? NSCursor.openHand : NSCursor.arrow).set() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var thumbnails: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.photos, id: \.self) { url in
                    Thumbnail(url: url, selected: model.selected == url, moved: model.overrides[url] != nil,
                              select: { model.selected = url }, remove: { model.remove(url) })
                }
                Button { choosePhotos() } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .medium))
                        .frame(width: 72, height: 72)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .instantTip("Add photos", above: true)
            }
            .padding(.vertical, 4)
        }
        .frame(height: 84)
    }

    // MARK: Settings

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("Watermark")
            HStack(spacing: 6) {
                choice("Text", on: model.watermark.kind == .text) { model.watermark.kind = .text }
                choice("Image", on: model.watermark.kind == .image) {
                    model.watermark.kind = .image
                    if model.watermark.imagePath == nil { WatermarkControls.chooseImage { model.watermark.imagePath = $0 } }
                }
            }
            WatermarkControls(watermark: $model.watermark)

            section("Position")
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("All photos").font(Leaf.font(12, .medium)).opacity(0.7)
                    PositionGrid(selection: model.watermark.position) { model.watermark.position = $0 }
                }
                if let url = model.selected {
                    let own = model.overrides[url]
                    VStack(alignment: .leading, spacing: 6) {
                        Text("This photo").font(Leaf.font(12, .medium)).opacity(0.7)
                        PositionGrid(selection: own.map { $0.center == nil ? $0.position : -1 } ?? model.watermark.position) {
                            model.overrides[url] = .init(position: $0, center: nil)
                        }
                        Button("Same as the others") { model.overrides[url] = nil }
                            .buttonStyle(.plain).font(Leaf.font(11, .semibold)).foregroundStyle(Leaf.ink)
                            .opacity(own == nil ? 0.35 : 1)
                            .disabled(own == nil)
                    }
                }
            }
            Text("Or drag the watermark on the photo.").font(Leaf.font(11)).opacity(0.6)

            section("Save")
            HStack(spacing: 6) {
                choice("As the original", on: model.format == .original) { model.format = .original }
                choice("PNG", on: model.format == .png) { model.format = .png }
                choice("JPEG", on: model.format == .jpeg) { model.format = .jpeg }
            }
            HStack {
                Text(model.folder.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "—")
                    .font(Leaf.font(11)).lineLimit(1).truncationMode(.middle).opacity(0.7)
                Spacer()
                Button("Choose…") { chooseFolder() }.buttonStyle(LeafButtonStyle())
            }
            Text("Photos keep their size, colour profile and metadata. PNG is lossless; JPEG and HEIC are written at maximum quality. The originals stay untouched.")
                .font(Leaf.font(11)).opacity(0.6).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A tile like the editor's tools: green when on.
    private func choice(_ title: LocalizedStringKey, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Leaf.font(12, .semibold))
                .foregroundStyle(on ? Leaf.ink : Color.primary.opacity(0.8))
                .padding(.horizontal, 10).frame(height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(on ? AnyShapeStyle(Leaf.selection) : AnyShapeStyle(.primary.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(on ? AnyShapeStyle(Leaf.markGradient) : AnyShapeStyle(.clear), lineWidth: 1.2))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func section(_ title: LocalizedStringKey) -> some View {
        Text(title).font(Leaf.font(11, .semibold)).textCase(.uppercase).opacity(0.5).padding(.top, 4)
    }

    // MARK: Helpers

    private func choosePhotos() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = BatchWatermark.imageTypes
        panel.allowsMultipleSelection = true
        WatermarkControls.present(panel) { model.add($0) }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        WatermarkControls.present(panel) { model.outputFolder = $0.first }
    }

    static func fit(_ size: CGSize, in room: CGSize) -> CGSize {
        let k = min(room.width / max(size.width, 1), room.height / max(size.height, 1))
        return CGSize(width: size.width * k, height: size.height * k)
    }

    /// Upright, at most 2000 px — the mark scales with the width, so it looks as on the full photo.
    static func loadPreview(_ url: URL) async -> CGImage? {
        await Task.detached { thumbnail(url, maxPixels: 2000) }.value
    }

    nonisolated static func thumbnail(_ url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary)
    }
}

/// A photo in the strip: selected = green ring, moved mark = a dot, × removes.
private struct Thumbnail: View {
    let url: URL
    let selected: Bool
    let moved: Bool
    let select: () -> Void
    let remove: () -> Void
    @State private var image: CGImage?
    @State private var hovered = false

    var body: some View {
        Button(action: select) {
            Group {
                if let image { Image(decorative: image, scale: 1).resizable().scaledToFill() } else { Color.primary.opacity(0.06) }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? Leaf.ink : .clear, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            if moved { Circle().fill(Leaf.leaf).frame(width: 10, height: 10).overlay(Circle().stroke(.white, lineWidth: 1.5)).padding(5) }
        }
        .overlay(alignment: .topTrailing) {
            if hovered {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 18, height: 18).background(Circle().fill(.black.opacity(0.6)))
                }
                .buttonStyle(.plain)
                .padding(3)
            }
        }
        .onHover { hovered = $0 }
        .instantTip(url.lastPathComponent, above: true)
        .task(id: url) { image = await Task.detached { BatchWatermarkView.thumbnail(url, maxPixels: 200) }.value }
    }
}
