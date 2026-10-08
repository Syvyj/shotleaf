import AppKit
import Observation

/// One mark on a screenshot. Coordinates are in *image points* — origin at the
/// image's top-left, y down — so marks stay glued to the shot when the canvas
/// around it grows, and may lie outside the image (on the canvas).
struct Annotation: Identifiable, Equatable {
    enum Kind: Equatable {
        case arrow(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case highlight(CGRect)
        case blur(CGRect)
        case step(center: CGPoint, number: Int)
        case text(origin: CGPoint, string: String)
        /// "Smart eraser": paints the area with the color around it (wipes text
        /// off a plain background).
        case erase(CGRect, fill: NSColor)
        /// A cut-out piece of the image moved by `offset`; its old place is
        /// erased like `.erase`.
        case piece(source: CGRect, offset: CGSize, fill: NSColor)
        /// Spotlight: everything in the image outside the area is dimmed.
        case focus(CGRect)
        case ellipse(CGRect)
        /// The part of the canvas to keep on export (at most one per shot).
        case crop(CGRect)
    }

    let id = UUID()
    var kind: Kind
    var color: AnnotationColor
    /// Line thickness for arrows and boxes, in image points.
    var lineWidth: CGFloat = AnnotationStyle.stroke

    /// Area the mark covers (for export bounds), in image points.
    var bounds: CGRect {
        switch kind {
        case .arrow(let a, let b):
            let head = AnnotationStyle.arrowHead(for: lineWidth)
            return CaptureMath.rect(a, b).insetBy(dx: -head, dy: -head)
        case .rectangle(let r), .ellipse(let r):
            return r.insetBy(dx: -lineWidth, dy: -lineWidth)
        case .crop(let r):
            return r
        case .highlight(let r), .blur(let r):
            return r
        case .erase(let r, _), .focus(let r):
            return r
        case .piece(let source, let offset, _):
            return source.union(source.offsetBy(dx: offset.width, dy: offset.height))
        case .step(let c, _):
            let r = AnnotationStyle.stepRadius
            return CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        case .text(let o, let s):
            let size = NSAttributedString(string: s, attributes: AnnotationStyle.textAttributes(color: .black)).size()
            return CGRect(origin: o, size: size).insetBy(dx: -6, dy: -4)
        }
    }
}

enum CaptureMath {
    static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

/// The palette: a strong default plus a few contrasting choices.
enum AnnotationColor: String, CaseIterable, Identifiable {
    case coral, amber, leaf, sky, ink, white
    var id: String { rawValue }

    var nsColor: NSColor {
        switch self {
        case .coral: NSColor(srgbRed: 0.96, green: 0.30, blue: 0.27, alpha: 1)
        case .amber: NSColor(srgbRed: 0.98, green: 0.72, blue: 0.16, alpha: 1)
        case .leaf: NSColor(srgbRed: 0.45, green: 0.74, blue: 0.20, alpha: 1)
        case .sky: NSColor(srgbRed: 0.20, green: 0.56, blue: 0.98, alpha: 1)
        case .ink: NSColor(srgbRed: 0.10, green: 0.12, blue: 0.10, alpha: 1)
        case .white: .white
        }
    }
}

enum AnnotationTool: String, CaseIterable, Identifiable {
    case arrow, rectangle, text, highlight, blur, step, erase, cut, focus, ellipse, crop
    var id: String { rawValue }

    var title: String {
        switch self {
        case .arrow: "Arrow"
        case .rectangle: "Box"
        case .text: "Text"
        case .highlight: "Marker"
        case .blur: "Blur"
        case .step: "Steps"
        case .erase: "Erase"
        case .cut: "Cut"
        case .focus: "Focus"
        case .ellipse: "Oval"
        case .crop: "Crop"
        }
    }

    /// Tools whose marks have a line thickness.
    var usesLineWidth: Bool { self == .arrow || self == .rectangle || self == .ellipse }

    /// 1…9 for the original tools (kept stable), letters for later ones —
    /// none of them clash with P / T / A in the toolbar.
    var key: Character {
        switch self {
        case .ellipse: "o"
        case .crop: "c"
        default: Character(String((Self.allCases.firstIndex(of: self) ?? 0) + 1))
        }
    }
}

/// The marks on one screenshot, with undo/redo and the tool/color in use.
@MainActor
@Observable
final class AnnotationDocument {
    /// The picture marks are drawn on, after "Apply crop" (nil = the original).
    struct Base: Equatable {
        let image: CGImage
        /// In image points.
        let size: CGSize
    }

    /// One undo step: the marks and the picture under them.
    private struct Snapshot {
        var items: [Annotation]
        var base: Base?
    }

    private(set) var items: [Annotation] = []
    private(set) var base: Base?
    private var redoStack: [Snapshot] = []
    private var undoStack: [Snapshot] = []

    /// nil = Select: click a mark to select, move, resize or delete it.
    var tool: AnnotationTool?
    var color: AnnotationColor = .coral
    var lineWidth: CGFloat = AnnotationStyle.stroke
    /// The mark showing handles (newly drawn marks are selected too).
    var selection: Annotation.ID?

    var selected: Annotation? { items.first { $0.id == selection } }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isEmpty: Bool { items.isEmpty }

    /// The next step badge number.
    var nextStep: Int {
        items.reduce(0) { if case .step(_, let n) = $1.kind { max($0, n) } else { $0 } } + 1
    }

    /// The crop area, if any.
    var crop: CGRect? {
        items.lazy.compactMap { if case .crop(let r) = $0.kind { r } else { nil } }.first
    }

    /// Adds a mark in the current color/width and selects it. A new crop
    /// replaces the old one.
    @discardableResult
    func add(_ kind: Annotation.Kind) -> Annotation.ID {
        let item = Annotation(kind: kind, color: color, lineWidth: lineWidth)
        var kept = items
        if case .crop = kind { kept.removeAll { if case .crop = $0.kind { true } else { false } } }
        commit(kept + [item])
        selection = item.id
        return item.id
    }

    func remove(_ id: Annotation.ID) {
        commit(items.filter { $0.id != id })
        if selection == id { selection = nil }
    }

    /// Recolors / re-thickens one mark (the selected one, from the toolbar).
    func restyle(_ id: Annotation.ID, color: AnnotationColor? = nil, lineWidth: CGFloat? = nil) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var new = items
        if let color { new[i].color = color }
        if let lineWidth { new[i].lineWidth = lineWidth }
        guard new != items else { return }
        commit(new)
    }

    /// Replaces one mark (e.g. a cut piece after it was moved) — one undo step.
    func update(_ id: Annotation.ID, to kind: Annotation.Kind) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var new = items
        new[i].kind = kind
        commit(new)
    }

    /// "Apply crop": keep only the cropped part of the picture for good (still
    /// undoable). Marks shift with it and stay editable; the crop mark goes.
    /// - Parameters: the original picture, used until a crop has been applied.
    func applyCrop(original image: CGImage, size: CGSize) {
        let current = base ?? Base(image: image, size: size)
        guard let crop else { return }
        let area = crop.intersection(CGRect(origin: .zero, size: current.size)).integral
        let scale = CGFloat(current.image.width) / current.size.width
        guard !area.isEmpty,
              let cropped = current.image.cropping(to: CGRect(x: area.minX * scale, y: area.minY * scale,
                                                              width: area.width * scale, height: area.height * scale))
        else { return }
        let shift = CGSize(width: -area.minX, height: -area.minY)
        let kept = items.compactMap { item -> Annotation? in
            if case .crop = item.kind { return nil }
            var moved = item
            moved.kind = AnnotationEditing.shiftedWithPicture(item.kind, by: shift)
            return moved
        }
        undoStack.append(Snapshot(items: items, base: base))
        redoStack.removeAll()
        items = kept
        base = Base(image: cropped, size: area.size)
        selection = nil
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(Snapshot(items: items, base: base))
        (items, base) = (previous.items, previous.base)
        dropStaleSelection()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(items: items, base: base))
        (items, base) = (next.items, next.base)
        dropStaleSelection()
    }

    private func dropStaleSelection() {
        if let selection, !items.contains(where: { $0.id == selection }) { self.selection = nil }
    }

    private func commit(_ new: [Annotation]) {
        undoStack.append(Snapshot(items: items, base: base))
        redoStack.removeAll()
        items = new
    }
}

/// Sizes shared by the live view and the export, in image points.
enum AnnotationStyle {
    static let stroke: CGFloat = 4
    /// S / M / L line thickness choices.
    static let widths: [CGFloat] = [2.5, 4, 7]
    static let arrowHead: CGFloat = 18
    /// The head grows with the line so thick arrows don't look stubby.
    static func arrowHead(for width: CGFloat) -> CGFloat { 10 + width * 2 }
    static let stepRadius: CGFloat = 15
    static let blurBlock: CGFloat = 10 // pixelation cell, in image points

    static func textAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        let font = NSFont.systemFont(ofSize: 22, weight: .bold)
        let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 22) } ?? font
        return [.font: rounded, .foregroundColor: color, .shadow: shadow]
    }
}
