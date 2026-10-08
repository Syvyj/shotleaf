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
/// the window, annotation tools (1–8), and the actions, in the "Leaves" style.
/// Keyboard: ↩/⌘C copy, ⌘S save, P pin, T text, A ask, 1–8 tools, ⌘Z undo,
/// esc — drop the tool, then close.
struct ScreenshotView: View {
    let image: NSImage
    let cgImage: CGImage
    let pixelSize: CGSize
    let displaySize: CGSize
    let actions: ScreenshotActions
    @Bindable var doc: AnnotationDocument

    @State private var toast: String?
    @State private var dragStart: CGPoint?
    @State private var dragNow: CGPoint?
    /// The cut piece being moved, and its offset when the drag began.
    @State private var moving: (id: Annotation.ID, startOffset: CGSize)?
    @State private var textDraft: (origin: CGPoint, string: String)?
    @FocusState private var textFocused: Bool

    /// Wide enough for the tool row, the toolbar and the hint line.
    static let minContentWidth: CGFloat = 600

    private var editingText: Bool { textDraft != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            toolRow
            canvas
            toolbar
            HintBar(items: [("↩", "copy & close"), ("⌘S", "save"), ("1–8", "tools"), ("⌘Z", "undo"), ("esc", doc.tool == nil ? "close" : "drop tool")])
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

    // MARK: Header & tools

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

    private var toolRow: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationTool.allCases) { tool in
                let on = doc.tool == tool
                Button { doc.tool = on ? nil : tool } label: {
                    HStack(spacing: 4) {
                        Text(String(tool.key)).font(Leaf.font(10, .bold)).opacity(0.55)
                        Text(tool.title).font(Leaf.font(12, on ? .semibold : .medium))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(on ? AnyShapeStyle(Leaf.selection) : AnyShapeStyle(.primary.opacity(0.05)))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(on ? AnyShapeStyle(Leaf.markGradient) : AnyShapeStyle(.clear), lineWidth: 1.2)
                    }
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(tool.key), modifiers: [])
                .disabled(editingText)
            }
            Spacer(minLength: 8)
            ForEach(AnnotationColor.allCases) { color in
                Button { doc.color = color } label: {
                    Circle()
                        .fill(Color(nsColor: color.nsColor))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
                        .padding(3)
                        .overlay(Circle().strokeBorder(doc.color == color ? Leaf.ink : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
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
        }
    }

    // MARK: Canvas

    /// The image at its own size, centred on a canvas that grows with the
    /// window; marks are drawn over both (in image points).
    private var canvas: some View {
        GeometryReader { geo in
            let origin = CGPoint(x: (geo.size.width - displaySize.width) / 2, y: (geo.size.height - displaySize.height) / 2)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.primary.opacity(0.035))
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: displaySize.width, height: displaySize.height)
                    .clipShape(RoundedRectangle(cornerRadius: doc.isEmpty ? 8 : 0, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    .offset(x: origin.x, y: origin.y)
                    .onDrag { NSItemProvider(contentsOf: actions.dragFile()) ?? NSItemProvider() }
                    .help(doc.tool == nil ? "Drag into any app" : "")
                Canvas { context, _ in
                    context.translateBy(x: origin.x, y: origin.y)
                    context.withCGContext { cg in
                        AnnotationRenderer.draw(visibleItems, image: cgImage, imageSize: displaySize, in: cg)
                    }
                }
                .allowsHitTesting(false)
                if doc.tool != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(drawGesture(origin: origin))
                        .onHover { inside in (inside ? NSCursor.crosshair : NSCursor.arrow).set() }
                }
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
                    .onExitCommand { textDraft = nil }
                }
            }
        }
        .frame(minWidth: displaySize.width, maxWidth: .infinity, minHeight: displaySize.height, maxHeight: .infinity)
    }

    /// Committed marks plus the one being drawn or moved right now.
    private var visibleItems: [Annotation] {
        var items = doc.items
        if let moving, let start = dragStart, let now = dragNow,
           let i = items.firstIndex(where: { $0.id == moving.id }),
           case .piece(let source, _, let fill) = items[i].kind {
            items[i].kind = .piece(source: source, offset: CGSize(width: moving.startOffset.width + now.x - start.x,
                                                                 height: moving.startOffset.height + now.y - start.y), fill: fill)
        } else if let kind = pendingKind(final: false) {
            items.append(Annotation(kind: kind, color: doc.color))
        }
        return items
    }

    private func drawGesture(origin: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let p = CGPoint(x: value.location.x - origin.x, y: value.location.y - origin.y)
                if dragStart == nil {
                    dragStart = p
                    if doc.tool == .cut, let hit = piece(at: p) { moving = hit }
                }
                dragNow = p
            }
            .onEnded { _ in
                defer { dragStart = nil; dragNow = nil; moving = nil }
                if let moving, let start = dragStart, let now = dragNow,
                   let item = doc.items.first(where: { $0.id == moving.id }),
                   case .piece(let source, _, let fill) = item.kind {
                    doc.update(moving.id, to: .piece(source: source, offset: CGSize(
                        width: moving.startOffset.width + now.x - start.x, height: moving.startOffset.height + now.y - start.y), fill: fill))
                    return
                }
                if doc.tool == .text, let at = dragNow {
                    textDraft = (at, "")
                    textFocused = true
                    return
                }
                if let kind = pendingKind(final: true) { doc.add(kind) }
            }
    }

    /// The topmost cut piece under `p` (in its moved position).
    private func piece(at p: CGPoint) -> (id: Annotation.ID, startOffset: CGSize)? {
        for item in doc.items.reversed() {
            if case .piece(let source, let offset, _) = item.kind,
               source.offsetBy(dx: offset.width, dy: offset.height).contains(p) {
                return (item.id, offset)
            }
        }
        return nil
    }

    /// What the current drag would create. `final` adds the expensive bits
    /// (sampling the erase color) only once, on release.
    private func pendingKind(final: Bool) -> Annotation.Kind? {
        guard let tool = doc.tool, let a = dragStart, let b = dragNow, moving == nil else { return nil }
        let rect = CaptureMath.rect(a, b)
        let big = rect.width >= 4 && rect.height >= 4
        switch tool {
        case .arrow: return hypot(b.x - a.x, b.y - a.y) > 4 ? .arrow(from: a, to: b) : nil
        case .rectangle: return big ? .rectangle(rect) : nil
        case .highlight: return big ? .highlight(rect) : nil
        case .blur: return big ? .blur(rect) : nil
        case .step: return final ? .step(center: b, number: doc.nextStep) : .step(center: b, number: doc.nextStep)
        case .text: return nil
        case .erase:
            guard big else { return nil }
            return .erase(rect, fill: final ? AnnotationRenderer.surroundingColor(of: rect, image: cgImage, imageSize: displaySize) : .gray.withAlphaComponent(0.5))
        case .cut:
            guard big else { return nil }
            if final {
                return .piece(source: rect, offset: .zero, fill: AnnotationRenderer.surroundingColor(of: rect, image: cgImage, imageSize: displaySize))
            }
            return .rectangle(rect) // outline while selecting
        }
    }

    private func commitText() {
        if let draft = textDraft, !draft.string.trimmingCharacters(in: .whitespaces).isEmpty {
            doc.add(.text(origin: draft.origin, string: draft.string))
        }
        textDraft = nil
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
            Button("Close") { actions.close() }
                .buttonStyle(LeafButtonStyle())
        }
    }

    /// Esc and ↩ — off while typing a text mark, so they reach the text field.
    @ViewBuilder
    private var keyboard: some View {
        if !editingText {
            Button("") { if doc.tool != nil { doc.tool = nil } else { actions.close() } }
                .keyboardShortcut(.cancelAction)
            Button("") { actions.copy(); actions.close() }
                .keyboardShortcut(.defaultAction)
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
