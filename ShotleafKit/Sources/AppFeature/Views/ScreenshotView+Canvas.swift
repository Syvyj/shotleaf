import SwiftUI
import AppKit
import VisionKit
import UniformTypeIdentifiers

/// The editor's canvas: the picture, the marks on it and the gestures.
extension ScreenshotView {
    // MARK: Canvas

    /// The image at its own size, centred on a canvas that grows with the
    /// window; marks are drawn over both (in image points).
    var canvas: some View {
        GeometryReader { geo in
            let origin = CGPoint(x: (geo.size.width - pictureSize.width) / 2, y: (geo.size.height - pictureSize.height) / 2)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.primary.opacity(0.035))
                if let backdrop = doc.backdrop {
                    let area = AnnotationRenderer.exportBounds(visibleItems, imageSize: pictureSize)
                        .insetBy(dx: -backdrop.padding, dy: -backdrop.padding)
                    Rectangle().fill(backdrop.style)
                        .frame(width: area.width, height: area.height)
                        .offset(x: origin.x + area.minX, y: origin.y + area.minY)
                }
                Image(nsImage: pictureNS)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: pictureSize.width, height: pictureSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: doc.backdrop?.corner ?? (doc.isEmpty ? 8 : 0), style: .continuous))
                    .shadow(color: .black.opacity(doc.backdrop == nil ? 0.12 : 0.28), radius: doc.backdrop == nil ? 6 : 12, y: 3)
                    .offset(x: origin.x, y: origin.y)
                Canvas { context, _ in
                    context.translateBy(x: origin.x, y: origin.y)
                    context.withCGContext { cg in
                        AnnotationRenderer.draw(visibleItems, image: pictureCG, imageSize: pictureSize, in: cg)
                        doc.watermark?.draw(in: cg, area: AnnotationRenderer.exportBounds(visibleItems, imageSize: pictureSize))
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
                // In Select mode, pressing on the shot (not on a
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
    func drawSelection(_ item: Annotation, in context: inout GraphicsContext) {
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
    var visibleItems: [Annotation] {
        var items = doc.items.filter { $0.id != editingTextID }
        if let live = liveEdit, let i = items.firstIndex(where: { $0.id == live.id }) {
            items[i].kind = live.kind
        } else if case .draw = drag, let kind = pendingKind(final: false) {
            items.append(Annotation(kind: kind, color: doc.color, lineWidth: doc.lineWidth))
        }
        return items
    }

    var visibleSelection: Annotation? {
        guard let id = doc.selection else { return nil }
        return visibleItems.first { $0.id == id }
    }

    /// The move/resize in progress, applied to its mark.
    var liveEdit: (id: Annotation.ID, kind: Annotation.Kind)? {
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

    func pointerGesture(origin: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let p = CGPoint(x: value.location.x - origin.x, y: value.location.y - origin.y)
                if dragStart == nil { begin(at: p) }
                if case .draw = drag, doc.tool == .pen { addPenPoint(p) }
                dragNow = p
            }
            .onEnded { _ in
                finish()
                dragStart = nil
                dragNow = nil
                drag = nil
                penPoints = []
                penStraightFrom = nil
            }
    }

    /// Freehand, or with Shift a straight line (level, plumb or at 45°) on from
    /// where Shift was pressed; what was drawn before stays.
    func addPenPoint(_ p: CGPoint) {
        guard NSEvent.modifierFlags.contains(.shift) else {
            penStraightFrom = nil
            if penPoints.last.map({ hypot($0.x - p.x, $0.y - p.y) > 1.5 }) ?? true { penPoints.append(p) }
            return
        }
        if penPoints.isEmpty { penPoints.append(p) }
        let kept = penStraightFrom ?? penPoints.count
        penStraightFrom = kept
        penPoints = Array(penPoints.prefix(kept)) + [AnnotationEditing.angleSnapped(penPoints[kept - 1], p)]
    }

    /// Decide what this drag is: a handle of the selected mark, a mark (select
    /// + move), or empty space (draw with the tool / deselect).
    func begin(at p: CGPoint) {
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

    func finish() {
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

    func updateCursor(_ p: CGPoint) {
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
    func pendingKind(final: Bool) -> Annotation.Kind? {
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
        case .magnify: // always round, from the corner dragged
            let side = max(rect.width, rect.height)
            return side >= 8 ? .magnify(CGRect(x: b.x < a.x ? a.x - side : a.x, y: b.y < a.y ? a.y - side : a.y, width: side, height: side)) : nil
        case .crop: return big ? .crop(rect) : nil
        case .ruler:
            let end = AnnotationEditing.snapped(a, b)
            return hypot(end.x - a.x, end.y - a.y) > 4 ? .measure(from: a, to: end) : nil
        case .erase: return big ? .erase(rect, fill: sampled()) : nil
        case .cut:
            guard big else { return nil }
            return final ? .piece(source: rect, offset: .zero, fill: sampled()) : .rectangle(rect) // outline while selecting
        case .pen: return penPoints.isEmpty ? nil : .pen(penPoints)
        case .text, .step: return nil
        }
    }

    func commitText() {
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
}
