import SwiftUI
import AppKit
import VisionKit
import UniformTypeIdentifiers

/// The window after a capture: the shot on a canvas that grows with
/// the window, annotation tools (0–9), and the actions, in the "Leaves" style.
/// Click a mark to select it: drag to move, drag handles to resize, ⌫ deletes.
/// In Select mode, dragging the shot itself drops the whole result into any app.
/// Keyboard: ⌘C (or ↩) copy, ⌘S save, P pin, T select text (Live Text), 0 select, 1–9 tools,
/// ⌘Z undo, esc — deselect / drop the tool, then close.
struct ScreenshotView: View {
    let image: NSImage
    let cgImage: CGImage
    let pixelSize: CGSize
    let displaySize: CGSize
    let actions: ScreenshotActions
    @Bindable var doc: AnnotationDocument
    @AppStorage(Self.closeAfterCopyKey) var closeAfterCopy = true
    static let closeAfterCopyKey = "closeAfterCopy"

    /// What the current pointer drag is doing.
    enum Drag {
        case draw
        case move(Annotation.ID, original: Annotation.Kind)
        case resize(Annotation.ID, AnnotationEditing.Handle, original: Annotation.Kind)
        case tap
    }

    @State var toast: String?
    @State var findingPrivate = false
    /// The first few times the editor opens: which keys do the main things.
    @State var keysHint = EditorHint.take()
    @State var dragStart: CGPoint?
    @State var dragNow: CGPoint?
    /// The pen line being drawn.
    @State var penPoints: [CGPoint] = []
    /// While Shift is held, the pen points kept from before it; the last one starts the straight line.
    @State var penStraightFrom: Int?
    @State var drag: Drag?
    @State var textDraft: (origin: CGPoint, string: String, width: CGFloat?, size: CGFloat)?
    /// The text mark being re-edited (double-click), hidden while its field is open.
    @State var editingTextID: Annotation.ID?
    /// For double-click detection on marks.
    @State var lastClick: (id: Annotation.ID, at: Date)?
    @FocusState var textFocused: Bool
    enum Flyout { case shapes, style, fontSize, backdrop, saveAs, watermark, link }
    @State var linking = false
    @State var removingBackground = false
    @State var flyout: Flyout?
    /// The shape the shapes button shows when another tool is in use.
    @State var lastShape: AnnotationTool = .arrow
    /// Live Text mode: the shot's text is selectable (nil = off).
    @State var liveText: ImageAnalysisOverlayView?

    /// Empty canvas around the shot from the start, for marks outside it.
    static let margin: CGFloat = 40

    /// Wide enough for the header (with the tools) and the action row.
    static let minContentWidth: CGFloat = 970

    var editingText: Bool { textDraft != nil }

    // The picture marks are drawn on: the capture, or its applied crop.
    var pictureCG: CGImage { doc.base?.image ?? cgImage }
    var pictureSize: CGSize { doc.base?.size ?? displaySize }
    var pictureNS: NSImage { doc.base.map { NSImage(cgImage: $0.image, size: $0.size) } ?? image }
    var picturePixels: CGSize { doc.base.map { CGSize(width: $0.image.width, height: $0.image.height) } ?? pixelSize }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header.zIndex(1) // tips and menus draw over the canvas
            canvas.overlay(alignment: .top) { toastPill }
                .overlay(alignment: .topTrailing) { privatePill }
                .overlay(alignment: .bottom) { keysHintPill }
            toolbar.zIndex(1) // its tips show above, over the canvas
        }
        .onChange(of: doc.tool) { _, tool in
            if let tool, Self.shapeTools.contains(tool) { lastShape = tool }
        }
        .onChange(of: doc.base) { liveText = nil } // its text is for the old picture
        .frame(minWidth: max(displaySize.width + 2 * Self.margin, Self.minContentWidth), maxWidth: .infinity,
               maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .leafPanelChrome()
        .overlay(alignment: .bottomTrailing) {
            WindowResizeGrip().frame(width: 12, height: 12).padding(2) // stays inside the 14pt margin
        }
        .overlay(WindowEdgeResizer()) // grab any edge or corner
        .background { keyboard }
    }

    // MARK: Header & tools

    /// Name and size on the left, the tools right after; the empty parts
    /// drag the window.
    var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                BrandLogo()
                VStack(alignment: .leading, spacing: 0) {
                    Text("Screenshot").font(Leaf.font(15, .semibold))
                    Text(verbatim: "\(Int(picturePixels.width)) × \(Int(picturePixels.height))") // no locale grouping
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .opacity(0.5)
                }
                .fixedSize()
            }
            .overlay(WindowDragArea())
            toolRow
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: 36)
                .overlay(WindowDragArea())
        }
    }

    /// "1 arrow · 5 blur · C crop · ⌘C copy": the main keys, for the first few shots
    /// (each tool also names itself on hover). The user's own keys, if they changed them.
    @ViewBuilder var keysHintPill: some View {
        if keysHint {
            HStack(spacing: 10) {
                Text(EditorHint.text).font(Leaf.font(12, .medium))
                Button { withAnimation { keysHint = false }; EditorHint.dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Hide"))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.72)))
            .padding(.bottom, 12)
            .transition(.opacity)
        }
    }

    /// With Blur picked: blurs faces, emails, phone numbers, cards and tokens in one go.
    @ViewBuilder var privatePill: some View {
        if doc.tool == .blur {
            Button {
                findingPrivate = true
                Task {
                    let spots = await PrivateSpots.find(in: pictureCG, size: pictureSize)
                    doc.add(all: spots.map { .blur($0) })
                    findingPrivate = false
                    flash(spots.isEmpty ? String(localized: "Nothing private found") : String(localized: "Blurred \(spots.count)"))
                }
            } label: {
                HStack(spacing: 6) {
                    if findingPrivate { ProgressView().controlSize(.small) } else { Image(systemName: "eye.slash") }
                    Text("Blur private info")
                }
                .font(Leaf.font(12, .semibold))
            }
            .buttonStyle(LeafButtonStyle())
            .disabled(findingPrivate)
            .instantTip("Faces, emails, phone numbers, card numbers and tokens")
            .padding(12)
        }
    }

    /// "Copied", "Saved to…": a pill over the top of the shot, never in the way of the tools.
    @ViewBuilder
    var toastPill: some View {
        if let toast {
            Text(LocalizedStringKey(toast))
                .font(Leaf.font(12, .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Leaf.leaf, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                .fixedSize()
                .padding(.top, 10)
                .allowsHitTesting(false)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Arrow, box, oval and magnifier share one button; its menu picks which.
    static let shapeTools: [AnnotationTool] = [.arrow, .rectangle, .ellipse, .magnify]
    static var toolbarTools: [AnnotationTool] {
        let ordered = AnnotationTool.ordered
        let firstShape = ordered.first { shapeTools.contains($0) }
        return ordered.filter { !shapeTools.contains($0) || $0 == firstShape }
    }

    var toolRow: some View {
        HStack(spacing: 4) {
            toolButton(nil, title: String(localized: "Select · drag the shot out"), key: "0")
            // The user's order; the three shapes share one button where the first of them sits.
            ForEach(Self.toolbarTools, id: \.self) { tool in
                if Self.shapeTools.contains(tool) { shapesButton } else { toolButton(tool, title: tool.title, key: tool.keyLabel) }
            }
            divider
            styleButton
            fontSizeButton
            backdropButton
        }
        .fixedSize(horizontal: false, vertical: true)
        .disabled(editingText)
    }

    var divider: some View {
        Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 22).padding(.horizontal, 4)
    }

    func tile(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(on ? AnyShapeStyle(Leaf.selection) : AnyShapeStyle(.primary.opacity(0.04)))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(on ? AnyShapeStyle(Leaf.markGradient) : AnyShapeStyle(.clear), lineWidth: 1.2)
            }
    }

    func pick(_ tool: AnnotationTool?) {
        if tool != nil { liveText = nil }
        doc.tool = tool
        if tool != nil { doc.selection = nil }
        flyout = nil
    }

    func toolButton(_ tool: AnnotationTool?, title: String, key: String) -> some View {
        let on = doc.tool == tool
        return Button { pick(tool) } label: {
            ToolIcon(tool: tool, size: 22)
                .foregroundStyle(on ? Leaf.ink : Color.primary.opacity(0.8))
                .frame(width: 38, height: 36)
                .background(tile(on))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .instantTip("\(title)  \(key.uppercased())")
    }

    var shapesButton: some View {
        let on = doc.tool.map(Self.shapeTools.contains) ?? false
        let shown = on ? doc.tool! : lastShape
        return HStack(spacing: 0) {
            Button { pick(shown) } label: {
                ToolIcon(tool: shown, size: 22).frame(width: 34, height: 36).contentShape(Rectangle())
            }
            Button { flyout = flyout == .shapes ? nil : .shapes } label: {
                chevron.frame(width: 16, height: 36).contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(on ? Leaf.ink : Color.primary.opacity(0.8))
        .background(tile(on))
        .instantTip("\(shown.title)  \(shown.keyLabel)", hidden: flyout == .shapes)
        .overlay(alignment: .topLeading) {
            if flyout == .shapes {
                flyoutCard {
                    ForEach(Self.shapeTools) { tool in
                        Button { pick(tool) } label: {
                            HStack(spacing: 10) {
                                ToolIcon(tool: tool, size: 20)
                                Text(tool.title).font(Leaf.font(13, .medium))
                                Spacer(minLength: 16)
                                if tool.key != nil { Keycap(key: tool.keyLabel) }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .frame(width: 150)
                            .background(tile(doc.tool == tool).opacity(doc.tool == tool ? 1 : 0))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// The current color and thickness; its menu changes both (for the
    /// selected mark too).
    var styleButton: some View {
        Button { flyout = flyout == .style ? nil : .style } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(nsColor: currentColor.nsColor))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
                WidthIcon(width: currentWidth)
                chevron
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(tile(flyout == .style))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .instantTip("Color & thickness", hidden: flyout == .style)
        .overlay(alignment: .topLeading) {
            if flyout == .style {
                flyoutCard {
                    HStack(spacing: 6) {
                        ForEach(AnnotationColor.allCases) { color in
                            Button { setColor(color) } label: {
                                Circle()
                                    .fill(Color(nsColor: color.nsColor))
                                    .frame(width: 20, height: 20)
                                    .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(currentColor == color ? Leaf.ink : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(Array(AnnotationStyle.widths.enumerated()), id: \.offset) { i, width in
                            let on = abs(currentWidth - width) < 0.1
                            Button { setWidth(width) } label: {
                                HStack(spacing: 4) {
                                    WidthIcon(width: width)
                                    Text([String(localized: "Thin"), String(localized: "Medium"), String(localized: "Thick")][i]).font(Leaf.font(12, .medium))
                                }
                                .padding(.horizontal, 6).frame(height: 28)
                                .background(tile(on).opacity(on ? 1 : 0))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// Callout text size: for new text, and the selected callout.
    var fontSizeButton: some View {
        Button { flyout = flyout == .fontSize ? nil : .fontSize } label: {
            HStack(spacing: 5) {
                Text("Aa").font(Leaf.font(15, .bold))
                Text(verbatim: "\(Int(currentFontSize))").font(Leaf.font(12, .semibold)).monospacedDigit().opacity(0.6)
                chevron
            }
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(tile(flyout == .fontSize))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .instantTip("Text size", hidden: flyout == .fontSize)
        .overlay(alignment: .topLeading) {
            if flyout == .fontSize {
                flyoutCard {
                    ForEach(AnnotationStyle.fontSizes, id: \.self) { size in
                        let on = abs(currentFontSize - size) < 0.1
                        Button { setFontSize(size) } label: {
                            HStack {
                                Text("Aa").font(Leaf.font(min(size, 30), .bold))
                                Spacer(minLength: 16)
                                Text(verbatim: "\(Int(size))").font(Leaf.font(12, .semibold)).monospacedDigit().opacity(0.6)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .frame(width: 110)
                            .background(tile(on).opacity(on ? 1 : 0))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    var currentFontSize: CGFloat {
        if case .text(_, _, _, _, let size)? = doc.selected?.kind { size } else { doc.fontSize }
    }

    func setFontSize(_ size: CGFloat) {
        doc.fontSize = size
        flyout = nil
        if let selected = doc.selected, case .text(let o, let s, let tail, let w, _) = selected.kind {
            doc.update(selected.id, to: .text(origin: o, string: s, tail: tail, width: w, size: size))
        }
    }

    var chevron: some View {
        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).opacity(0.6)
    }

    func flyoutCard<Content: View>(above: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(Leaf.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .fixedSize()
            .offset(y: above ? -42 : 42)
    }
}
