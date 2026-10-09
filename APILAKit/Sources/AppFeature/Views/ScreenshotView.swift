import SwiftUI
import AppKit
import VisionKit

/// What the screenshot window can do; wired by `ScreenshotWindows`. Copy,
/// save, pin and drag use the screenshot *with* its annotations.
struct ScreenshotActions {
    var copy: () -> Void
    var save: () -> URL?
    var pin: () -> Void
    var text: () -> Void
    var ask: () -> Void
    var close: () -> Void
    /// A PNG file of the current result, for drag-and-drop into other apps.
    var dragFile: () -> URL?
}

/// Shottr-style window after a capture: the shot on a canvas that grows with
/// the window, annotation tools (0–9), and the actions, in the "Leaves" style.
/// Click a mark to select it: drag to move, drag handles to resize, ⌫ deletes.
/// In Select mode, dragging the shot itself drops the whole result into any app.
/// Keyboard: ↩/⌘C copy, ⌘S save, P pin, T text, A ask, 0 select, 1–9 tools,
/// ⌘Z undo, esc — deselect / drop the tool, then close.
struct ScreenshotView: View {
    let image: NSImage
    let cgImage: CGImage
    let pixelSize: CGSize
    let displaySize: CGSize
    let actions: ScreenshotActions
    @Bindable var doc: AnnotationDocument

    /// What the current pointer drag is doing.
    private enum Drag {
        case draw
        case move(Annotation.ID, original: Annotation.Kind)
        case resize(Annotation.ID, AnnotationEditing.Handle, original: Annotation.Kind)
        case tap
    }

    @State private var toast: String?
    @State private var dragStart: CGPoint?
    @State private var dragNow: CGPoint?
    @State private var drag: Drag?
    @State private var textDraft: (origin: CGPoint, string: String, width: CGFloat?, size: CGFloat)?
    /// The text mark being re-edited (double-click), hidden while its field is open.
    @State private var editingTextID: Annotation.ID?
    /// For double-click detection on marks.
    @State private var lastClick: (id: Annotation.ID, at: Date)?
    @FocusState private var textFocused: Bool
    private enum Flyout { case shapes, style, fontSize }
    @State private var flyout: Flyout?
    /// The shape the shapes button shows when another tool is in use.
    @State private var lastShape: AnnotationTool = .arrow
    /// Live Text mode: the shot's text is selectable (nil = off).
    @State private var liveText: ImageAnalysisOverlayView?

    /// Empty canvas around the shot from the start, for marks outside it.
    static let margin: CGFloat = 40

    /// Wide enough for the header (with the tools) and the action row.
    static let minContentWidth: CGFloat = 780

    private var editingText: Bool { textDraft != nil }

    // The picture marks are drawn on: the capture, or its applied crop.
    private var pictureCG: CGImage { doc.base?.image ?? cgImage }
    private var pictureSize: CGSize { doc.base?.size ?? displaySize }
    private var pictureNS: NSImage { doc.base.map { NSImage(cgImage: $0.image, size: $0.size) } ?? image }
    private var picturePixels: CGSize { doc.base.map { CGSize(width: $0.image.width, height: $0.image.height) } ?? pixelSize }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header.zIndex(1) // tips and menus draw over the canvas
            canvas
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
            WindowResizeGrip().frame(width: 18, height: 18).padding(4)
        }
        .overlay(WindowEdgeResizer()) // grab any edge or corner
        .background { keyboard }
    }

    // MARK: Header & tools

    /// Name and size on the left, the tools right after; the empty parts
    /// drag the window.
    private var header: some View {
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
                .overlay(alignment: .trailing) {
                    if let toast {
                        Text(toast)
                            .font(Leaf.font(12, .semibold))
                            .foregroundStyle(Leaf.ink)
                            .fixedSize()
                            .transition(.opacity)
                    }
                }
                .overlay(WindowDragArea())
        }
    }

    /// Arrow, box and oval share one button; its menu picks which.
    static let shapeTools: [AnnotationTool] = [.arrow, .rectangle, .ellipse]
    private static let singleTools = AnnotationTool.allCases.filter { !shapeTools.contains($0) }

    private var toolRow: some View {
        HStack(spacing: 4) {
            toolButton(nil, title: "Select · drag the shot out", key: "0")
            shapesButton
            ForEach(Self.singleTools) { tool in
                toolButton(tool, title: tool.title, key: tool.key)
            }
            divider
            styleButton
            fontSizeButton
        }
        .fixedSize(horizontal: false, vertical: true)
        .disabled(editingText)
    }

    private var divider: some View {
        Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 22).padding(.horizontal, 4)
    }

    private func tile(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(on ? AnyShapeStyle(Leaf.selection) : AnyShapeStyle(.primary.opacity(0.04)))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(on ? AnyShapeStyle(Leaf.markGradient) : AnyShapeStyle(.clear), lineWidth: 1.2)
            }
    }

    private func pick(_ tool: AnnotationTool?) {
        if tool != nil { liveText = nil }
        doc.tool = tool
        if tool != nil { doc.selection = nil }
        flyout = nil
    }

    private func toolButton(_ tool: AnnotationTool?, title: String, key: Character) -> some View {
        let on = doc.tool == tool
        return Button { pick(tool) } label: {
            ToolIcon(tool: tool, size: 22)
                .foregroundStyle(on ? Leaf.ink : Color.primary.opacity(0.8))
                .frame(width: 38, height: 36)
                .background(tile(on))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .instantTip("\(title)  \(String(key).uppercased())")
    }

    private var shapesButton: some View {
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
        .instantTip("\(shown.title)  \(String(shown.key).uppercased())", hidden: flyout == .shapes)
        .overlay(alignment: .topLeading) {
            if flyout == .shapes {
                flyoutCard {
                    ForEach(Self.shapeTools) { tool in
                        Button { pick(tool) } label: {
                            HStack(spacing: 10) {
                                ToolIcon(tool: tool, size: 20)
                                Text(tool.title).font(Leaf.font(13, .medium))
                                Spacer(minLength: 16)
                                Keycap(key: String(tool.key).uppercased())
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
    private var styleButton: some View {
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
                                    Text(["Thin", "Medium", "Thick"][i]).font(Leaf.font(12, .medium))
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
    private var fontSizeButton: some View {
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

    private var currentFontSize: CGFloat {
        if case .text(_, _, _, _, let size)? = doc.selected?.kind { size } else { doc.fontSize }
    }

    private func setFontSize(_ size: CGFloat) {
        doc.fontSize = size
        flyout = nil
        if let selected = doc.selected, case .text(let o, let s, let tail, let w, _) = selected.kind {
            doc.update(selected.id, to: .text(origin: o, string: s, tail: tail, width: w, size: size))
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).opacity(0.6)
    }

    private func flyoutCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(Leaf.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .fixedSize()
            .offset(y: 42)
    }

    // The toolbar shows — and edits — the selected mark's style when there is one.
    private var currentColor: AnnotationColor { doc.selected?.color ?? doc.color }
    private var currentWidth: CGFloat { doc.selected?.lineWidth ?? doc.lineWidth }

    private func setColor(_ color: AnnotationColor) {
        doc.color = color
        if let id = doc.selection { doc.restyle(id, color: color) }
    }

    private func setWidth(_ width: CGFloat) {
        doc.lineWidth = width
        if let id = doc.selection { doc.restyle(id, lineWidth: width) }
    }

    // MARK: Canvas

    /// The image at its own size, centred on a canvas that grows with the
    /// window; marks are drawn over both (in image points).
    private var canvas: some View {
        GeometryReader { geo in
            let origin = CGPoint(x: (geo.size.width - pictureSize.width) / 2, y: (geo.size.height - pictureSize.height) / 2)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.primary.opacity(0.035))
                Image(nsImage: pictureNS)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: pictureSize.width, height: pictureSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: doc.isEmpty ? 8 : 0, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    .offset(x: origin.x, y: origin.y)
                Canvas { context, _ in
                    context.translateBy(x: origin.x, y: origin.y)
                    context.withCGContext { cg in
                        AnnotationRenderer.draw(visibleItems, image: pictureCG, imageSize: pictureSize, in: cg)
                    }
                    if let selected = visibleSelection { drawSelection(selected, in: &context) }
                }
                .allowsHitTesting(false)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(pointerGesture(origin: origin))
                    .onContinuousHover { phase in
                        if case .active(let at) = phase { updateCursor(CGPoint(x: at.x - origin.x, y: at.y - origin.y)) }
                        else { NSCursor.arrow.set() }
                    }
                // Shottr-style: in Select mode, pressing on the shot (not on a
                // mark) drags the whole result out — marks included.
                DragOutView(
                    wantsDrag: { p in
                        flyout == nil && liveText == nil && doc.tool == nil && AnnotationEditing.hit(doc.items, at: p) == nil
                            && doc.selected.flatMap { AnnotationEditing.handle(of: $0.kind, at: p) } == nil
                    },
                    onPress: { doc.selection = nil },
                    file: actions.dragFile,
                    thumbnail: image
                )
                .frame(width: pictureSize.width, height: pictureSize.height)
                .offset(x: origin.x, y: origin.y)
                if let draft = textDraft {
                    TextField("Type, then ↩", text: Binding(
                        get: { textDraft?.string ?? "" }, set: { textDraft?.string = $0 }
                    ), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: draft.size, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(nsColor: doc.color.nsColor))
                    .frame(width: draft.width ?? AnnotationStyle.textWrap, alignment: .leading)
                    .padding(4)
                    .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: origin.x + draft.origin.x - 4, y: origin.y + draft.origin.y - 4)
                    .focused($textFocused)
                    .onSubmit(commitText)
                    .onExitCommand { textDraft = nil; editingTextID = nil; doc.tool = nil }
                }
                if let liveText {
                    LiveTextView(overlay: liveText, image: pictureCG)
                        .frame(width: pictureSize.width, height: pictureSize.height)
                        .offset(x: origin.x, y: origin.y)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)) // nothing spills over the toolbars
        .frame(minWidth: displaySize.width + 2 * Self.margin, maxWidth: .infinity,
               minHeight: displaySize.height + 2 * Self.margin, maxHeight: .infinity)
    }

    /// Dashed outline + round handles around the selected mark (screen only).
    private func drawSelection(_ item: Annotation, in context: inout GraphicsContext) {
        let frame = AnnotationEditing.frame(of: item.kind).insetBy(dx: -4, dy: -4)
        let outline = Path(roundedRect: frame, cornerRadius: 4)
        context.stroke(outline, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 3))
        context.stroke(outline, with: .color(Leaf.leaf), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        for (_, point) in AnnotationEditing.handles(of: item.kind) {
            let dot = Path(ellipseIn: CGRect(x: point.x - 5.5, y: point.y - 5.5, width: 11, height: 11))
            context.fill(dot, with: .color(.white))
            context.stroke(dot, with: .color(Leaf.leaf), style: StrokeStyle(lineWidth: 2))
        }
    }

    /// Committed marks, with the one being drawn / moved / resized right now.
    private var visibleItems: [Annotation] {
        var items = doc.items.filter { $0.id != editingTextID }
        if let live = liveEdit, let i = items.firstIndex(where: { $0.id == live.id }) {
            items[i].kind = live.kind
        } else if case .draw = drag, let kind = pendingKind(final: false) {
            items.append(Annotation(kind: kind, color: doc.color, lineWidth: doc.lineWidth))
        }
        return items
    }

    private var visibleSelection: Annotation? {
        guard let id = doc.selection else { return nil }
        return visibleItems.first { $0.id == id }
    }

    /// The move/resize in progress, applied to its mark.
    private var liveEdit: (id: Annotation.ID, kind: Annotation.Kind)? {
        guard let start = dragStart, let now = dragNow else { return nil }
        switch drag {
        case .move(let id, let original):
            return (id, AnnotationEditing.moved(original, by: CGSize(width: now.x - start.x, height: now.y - start.y)))
        case .resize(let id, let handle, let original):
            return (id, AnnotationEditing.resized(original, handle, to: now))
        default:
            return nil
        }
    }

    private func pointerGesture(origin: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let p = CGPoint(x: value.location.x - origin.x, y: value.location.y - origin.y)
                if dragStart == nil { begin(at: p) }
                dragNow = p
            }
            .onEnded { _ in
                finish()
                dragStart = nil
                dragNow = nil
                drag = nil
            }
    }

    /// Decide what this drag is: a handle of the selected mark, a mark (select
    /// + move), or empty space (draw with the tool / deselect).
    private func begin(at p: CGPoint) {
        dragStart = p
        flyout = nil
        if editingText {
            // A click away from the text field finishes the text (it doesn't
            // move the field around).
            commitText()
            drag = nil
        } else if let selected = doc.selected, let handle = AnnotationEditing.handle(of: selected.kind, at: p) {
            drag = .resize(selected.id, handle, original: selected.kind)
        } else if let id = AnnotationEditing.hit(doc.items, at: p), let item = doc.items.first(where: { $0.id == id }) {
            doc.selection = id
            drag = .move(id, original: item.kind)
        } else if let tool = doc.tool, tool != .text, tool != .step {
            doc.selection = nil
            drag = .draw
        } else {
            drag = .tap
        }
    }

    private func finish() {
        guard let start = dragStart, let now = dragNow else { return }
        let moved = hypot(now.x - start.x, now.y - start.y) > 1
        switch drag {
        case .move(let id, let original):
            if moved, let live = liveEdit { doc.update(live.id, to: live.kind); break }
            // A double-click on a text mark opens it for editing.
            if case .text(let origin, let string, _, let width, let size) = original,
               let last = lastClick, last.id == id, Date().timeIntervalSince(last.at) < 0.4 {
                if let item = doc.items.first(where: { $0.id == id }) { doc.color = item.color }
                editingTextID = id
                textDraft = (origin, string, width, size)
                textFocused = true
                lastClick = nil
            } else {
                lastClick = (id, Date())
            }
        case .resize:
            if moved, let live = liveEdit { doc.update(live.id, to: live.kind) }
        case .draw:
            if let kind = pendingKind(final: true) { doc.add(kind) }
        case .tap:
            switch doc.tool {
            case .text:
                textDraft = (now, "", nil, doc.fontSize)
                textFocused = true
            case .step:
                doc.add(.step(center: now, number: doc.nextStep))
            default:
                doc.selection = nil
            }
        case nil:
            break
        }
    }

    private func updateCursor(_ p: CGPoint) {
        if let selected = doc.selected, let handle = AnnotationEditing.handle(of: selected.kind, at: p) {
            (handle == .textWidth ? NSCursor.resizeLeftRight : .crosshair).set()
        } else if AnnotationEditing.hit(doc.items, at: p) != nil {
            NSCursor.openHand.set()
        } else if doc.tool != nil {
            (doc.tool == .text ? NSCursor.iBeam : NSCursor.crosshair).set()
        } else if CGRect(origin: .zero, size: pictureSize).contains(p) {
            NSCursor.openHand.set() // Select mode over the shot: drag it out
        } else {
            NSCursor.arrow.set()
        }
    }

    /// What the current drag would draw. `final` adds the expensive bits
    /// (sampling the erase color) only once, on release.
    private func pendingKind(final: Bool) -> Annotation.Kind? {
        guard let tool = doc.tool, let a = dragStart, let b = dragNow else { return nil }
        let rect = CaptureMath.rect(a, b)
        let big = rect.width >= 4 && rect.height >= 4
        func sampled() -> NSColor {
            final ? AnnotationRenderer.surroundingColor(of: rect, image: pictureCG, imageSize: pictureSize) : .gray.withAlphaComponent(0.5)
        }
        switch tool {
        case .arrow: return hypot(b.x - a.x, b.y - a.y) > 4 ? .arrow(from: a, to: b) : nil
        case .rectangle: return big ? .rectangle(rect) : nil
        case .highlight: return big ? .highlight(rect) : nil
        case .blur: return big ? .blur(rect) : nil
        case .focus: return big ? .focus(rect) : nil
        case .ellipse: return big ? .ellipse(rect) : nil
        case .crop: return big ? .crop(rect) : nil
        case .erase: return big ? .erase(rect, fill: sampled()) : nil
        case .cut:
            guard big else { return nil }
            return final ? .piece(source: rect, offset: .zero, fill: sampled()) : .rectangle(rect) // outline while selecting
        case .text, .step: return nil
        }
    }

    private func commitText() {
        let string = textDraft?.string.trimmingCharacters(in: .whitespaces) ?? ""
        if let draft = textDraft {
            if let id = editingTextID {
                // Editing: an emptied text removes the mark.
                if string.isEmpty { doc.remove(id) } else {
                    let tail: CGPoint? = if case .text(_, _, let t, _, _) = doc.items.first(where: { $0.id == id })?.kind { t } else { nil }
                    doc.update(id, to: .text(origin: draft.origin, string: draft.string, tail: tail, width: draft.width, size: draft.size))
                }
            } else if !string.isEmpty {
                doc.add(.text(origin: draft.origin, string: draft.string,
                              tail: AnnotationStyle.defaultTail(origin: draft.origin, string: draft.string, size: draft.size),
                              size: draft.size))
            }
        }
        textDraft = nil
        editingTextID = nil
        if doc.tool == .text { doc.tool = nil } // one text per click of the tool
    }

    // MARK: Toolbar

    /// Actions with their keys on them — one row instead of buttons + hints.
    private var toolbar: some View {
        HStack(spacing: 6) {
            Button { copy() } label: { keyed(liveText == nil ? "Copy" : "Copy text", "↩") }
                .buttonStyle(LeafButtonStyle(prominent: true))
                .keyboardShortcut("c", modifiers: .command)
            Button {
                if let url = actions.save() { flash("Saved to \(url.deletingLastPathComponent().lastPathComponent)") }
            } label: { keyed("Save", "⌘S") }
            .buttonStyle(LeafButtonStyle())
            .keyboardShortcut("s", modifiers: .command)
            Button { actions.pin() } label: { keyed("Pin", "P") }
                .buttonStyle(LeafButtonStyle())
                .keyboardShortcut("p", modifiers: [])
            Button { toggleLiveText() } label: { keyed("Text", "T") }
                .buttonStyle(LeafButtonStyle(prominent: liveText != nil))
                .keyboardShortcut("t", modifiers: [])
                .instantTip(liveText == nil ? "Select text on the shot" : "Back to marks", above: true)
            Button { actions.ask() } label: { keyed("Ask AI", "A") }
                .buttonStyle(LeafButtonStyle())
                .keyboardShortcut("a", modifiers: [])
            Spacer(minLength: 6)
            if doc.crop != nil {
                Button("Apply crop") { doc.applyCrop(original: cgImage, size: displaySize) }
                    .buttonStyle(LeafButtonStyle(prominent: true))
                    .instantTip("Keep only the cropped area — ⌘Z brings the rest back", above: true)
            }
            if doc.selection != nil {
                Button { if let id = doc.selection { doc.remove(id) } } label: { keyed("Delete", "⌫") }
                    .buttonStyle(LeafButtonStyle())
            }
            Button { doc.undo() } label: { keyed("Undo", "⌘Z") }
                .buttonStyle(LeafButtonStyle())
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!doc.canUndo)
                .opacity(doc.canUndo ? 1 : 0.4)
            Button { actions.close() } label: { keyed("Close", "esc") }
                .buttonStyle(LeafButtonStyle())
        }
        .disabled(editingText)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func keyed(_ title: String, _ key: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
            Text(key)
                .font(Leaf.font(10.5, .semibold))
                .opacity(0.5)
                .padding(.horizontal, 3).padding(.vertical, 1)
                .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
        }
    }

    /// Esc, ↩, ⌫ and tool keys — off while typing a text mark (they belong to
    /// the field then), except esc, which always drops the text being typed.
    @ViewBuilder
    private var keyboard: some View {
        if editingText {
            Button("") { textDraft = nil; editingTextID = nil; doc.tool = nil }
                .keyboardShortcut(.cancelAction)
        } else {
            Button("") {
                if flyout != nil { flyout = nil }
                else if liveText != nil { liveText = nil }
                else if doc.selection != nil { doc.selection = nil }
                else if doc.tool != nil { doc.tool = nil }
                else { actions.close() }
            }
            .keyboardShortcut(.cancelAction)
            Button("") { copy(); actions.close() }
                .keyboardShortcut(.defaultAction)
            Button("") { if let id = doc.selection { doc.remove(id) } }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(doc.selection == nil)
            Button("") { doc.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!doc.canRedo)
            Button("") { pick(nil) }.keyboardShortcut("0", modifiers: [])
            ForEach(AnnotationTool.allCases) { tool in
                Button("") { pick(tool) }.keyboardShortcut(KeyEquivalent(tool.key), modifiers: [])
            }
        }
    }

    /// The image — or, in Live Text mode, the selected text (all of it when
    /// nothing is selected).
    private func copy() {
        guard let liveText else { actions.copy(); flash("Copied"); return }
        let text = liveText.selectedText.isEmpty ? liveText.analysis?.transcript ?? "" : liveText.selectedText
        guard !text.isEmpty else { flash("No text found"); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flash(liveText.selectedText.isEmpty ? "Copied all text" : "Copied")
    }

    private func toggleLiveText() {
        if liveText != nil { liveText = nil; return }
        doc.tool = nil
        doc.selection = nil
        liveText = ImageAnalysisOverlayView()
        flash("Select text · ↩ copies it")
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
