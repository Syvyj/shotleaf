import SwiftUI
import AppKit

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
    @State private var textDraft: (origin: CGPoint, string: String)?
    /// The text mark being re-edited (double-click), hidden while its field is open.
    @State private var editingTextID: Annotation.ID?
    /// For double-click detection on marks.
    @State private var lastClick: (id: Annotation.ID, at: Date)?
    @FocusState private var textFocused: Bool

    /// Wide enough for the tool row (12 tools, 3 widths, 6 colors) in one line,
    /// and for the action row and the hint line.
    static let minContentWidth: CGFloat = 700

    private var editingText: Bool { textDraft != nil }

    // The picture marks are drawn on: the capture, or its applied crop.
    private var pictureCG: CGImage { doc.base?.image ?? cgImage }
    private var pictureSize: CGSize { doc.base?.size ?? displaySize }
    private var pictureNS: NSImage { doc.base.map { NSImage(cgImage: $0.image, size: $0.size) } ?? image }
    private var picturePixels: CGSize { doc.base.map { CGSize(width: $0.image.width, height: $0.image.height) } ?? pixelSize }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            toolRow
            canvas
            toolbar
            HintBar(items: [("↩", "copy & close"), ("⌘S", "save"), ("0–9 O C", "tools"), ("⌫", "delete"), ("⌘Z", "undo"), ("esc", escHint)])
        }
        .frame(minWidth: max(displaySize.width, Self.minContentWidth), maxWidth: .infinity,
               maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .leafPanelChrome()
        .overlay(alignment: .bottomTrailing) {
            WindowResizeGrip().frame(width: 18, height: 18).padding(4)
        }
        .overlay(WindowEdgeResizer()) // grab any edge or corner
        .background { keyboard }
    }

    private var escHint: String {
        doc.selection != nil ? "deselect" : doc.tool != nil ? "drop tool" : "close"
    }

    // MARK: Header & tools

    private var header: some View {
        HStack(spacing: 8) {
            BrandLogo()
            Text("Screenshot").font(Leaf.font(16, .semibold))
            Text(verbatim: "\(Int(picturePixels.width)) × \(Int(picturePixels.height))") // no locale grouping
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

    private var toolRow: some View {
        HStack(spacing: 3) {
            toolButton(nil, key: "0", title: "Select")
            ForEach(AnnotationTool.allCases) { tool in
                toolButton(tool, key: tool.key, title: tool.title)
            }
            divider
            ForEach(Array(AnnotationStyle.widths.enumerated()), id: \.offset) { i, width in
                let on = abs(currentWidth - width) < 0.1
                Button { setWidth(width) } label: {
                    WidthIcon(width: width)
                        .foregroundStyle(on ? Leaf.ink : Color.primary.opacity(0.75))
                        .frame(width: 26, height: 26)
                        .background(on ? AnyShapeStyle(Leaf.selection) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help(["Thin", "Medium", "Thick"][i] + " line")
            }
            divider
            ForEach(AnnotationColor.allCases) { color in
                Button { setColor(color) } label: {
                    Circle()
                        .fill(Color(nsColor: color.nsColor))
                        .frame(width: 15, height: 15)
                        .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
                        .padding(3)
                        .overlay(Circle().strokeBorder(currentColor == color ? Leaf.ink : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var divider: some View {
        Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 18).padding(.horizontal, 4)
    }

    private func toolButton(_ tool: AnnotationTool?, key: Character, title: String) -> some View {
        let on = doc.tool == tool
        return Button {
            doc.tool = tool
            if tool != nil { doc.selection = nil }
        } label: {
            ToolIcon(tool: tool)
                .foregroundStyle(on ? Leaf.ink : Color.primary.opacity(0.8))
                .frame(width: 30, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(on ? AnyShapeStyle(Leaf.selection) : AnyShapeStyle(.primary.opacity(0.04)))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(on ? AnyShapeStyle(Leaf.markGradient) : AnyShapeStyle(.clear), lineWidth: 1.2)
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(String(key)).font(.system(size: 7.5, weight: .bold, design: .rounded)).opacity(0.45).padding(2)
                }
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: "\(title) (\(key))"))
        .keyboardShortcut(KeyEquivalent(key), modifiers: [])
        .disabled(editingText)
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
                    wantsDrag: { p in doc.tool == nil && AnnotationEditing.hit(doc.items, at: p) == nil },
                    onPress: { doc.selection = nil },
                    file: actions.dragFile,
                    thumbnail: image
                )
                .frame(width: pictureSize.width, height: pictureSize.height)
                .offset(x: origin.x, y: origin.y)
                if let draft = textDraft {
                    TextField("Type, then ↩", text: Binding(
                        get: { textDraft?.string ?? "" }, set: { textDraft?.string = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(nsColor: doc.color.nsColor))
                    .frame(width: 320, alignment: .leading)
                    .padding(4)
                    .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: origin.x + draft.origin.x - 4, y: origin.y + draft.origin.y - 4)
                    .focused($textFocused)
                    .onSubmit(commitText)
                    .onExitCommand { textDraft = nil; editingTextID = nil }
                }
            }
        }
        .frame(minWidth: displaySize.width, maxWidth: .infinity, minHeight: displaySize.height, maxHeight: .infinity)
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
        if let selected = doc.selected, let handle = AnnotationEditing.handle(of: selected.kind, at: p) {
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
            if case .text(let origin, let string) = original,
               let last = lastClick, last.id == id, Date().timeIntervalSince(last.at) < 0.4 {
                if let item = doc.items.first(where: { $0.id == id }) { doc.color = item.color }
                editingTextID = id
                textDraft = (origin, string)
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
                textDraft = (now, "")
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
        if let selected = doc.selected, AnnotationEditing.handle(of: selected.kind, at: p) != nil {
            NSCursor.crosshair.set()
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
                if string.isEmpty { doc.remove(id) } else { doc.update(id, to: .text(origin: draft.origin, string: draft.string)) }
            } else if !string.isEmpty {
                doc.add(.text(origin: draft.origin, string: draft.string))
            }
        }
        textDraft = nil
        editingTextID = nil
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            Button("Copy") { actions.copy(); flash("Copied") }
                .buttonStyle(LeafButtonStyle(prominent: true))
                .keyboardShortcut("c", modifiers: .command)
                .disabled(editingText)
            Button("Save") {
                if let url = actions.save() { flash("Saved to \(url.deletingLastPathComponent().lastPathComponent)") }
            }
            .buttonStyle(LeafButtonStyle())
            .keyboardShortcut("s", modifiers: .command)
            Button("Pin") { actions.pin() }
                .buttonStyle(LeafButtonStyle())
                .keyboardShortcut("p", modifiers: [])
                .disabled(editingText)
            Button("Text") { actions.text() }
                .buttonStyle(LeafButtonStyle())
                .keyboardShortcut("t", modifiers: [])
                .disabled(editingText)
            Button("Ask AI") { actions.ask() }
                .buttonStyle(LeafButtonStyle())
                .keyboardShortcut("a", modifiers: [])
                .disabled(editingText)
            Spacer()
            if doc.crop != nil {
                Button("Apply crop") { doc.applyCrop(original: cgImage, size: displaySize) }
                    .buttonStyle(LeafButtonStyle(prominent: true))
                    .help(Text(verbatim: "Keep only the cropped area (⌘Z brings the rest back)"))
                    .disabled(editingText)
            }
            Button("Undo") { doc.undo() }
                .buttonStyle(LeafButtonStyle())
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!doc.canUndo || editingText)
                .opacity(doc.canUndo ? 1 : 0.4)
            Button("") { doc.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!doc.canRedo || editingText)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
            Button("Close") { actions.close() }
                .buttonStyle(LeafButtonStyle())
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Esc, ↩ and ⌫ — off while typing a text mark, so they reach the text field.
    @ViewBuilder
    private var keyboard: some View {
        if !editingText {
            Button("") {
                if doc.selection != nil { doc.selection = nil }
                else if doc.tool != nil { doc.tool = nil }
                else { actions.close() }
            }
            .keyboardShortcut(.cancelAction)
            Button("") { actions.copy(); actions.close() }
                .keyboardShortcut(.defaultAction)
            Button("") { if let id = doc.selection { doc.remove(id) } }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(doc.selection == nil)
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
