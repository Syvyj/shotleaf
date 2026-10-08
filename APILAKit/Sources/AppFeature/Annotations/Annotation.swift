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
    }

    let id = UUID()
    var kind: Kind
    var color: AnnotationColor

    /// Area the mark covers (for export bounds), in image points.
    var bounds: CGRect {
        switch kind {
        case .arrow(let a, let b):
            return CaptureMath.rect(a, b).insetBy(dx: -AnnotationStyle.arrowHead, dy: -AnnotationStyle.arrowHead)
        case .rectangle(let r), .highlight(let r), .blur(let r):
            return r.insetBy(dx: -AnnotationStyle.stroke, dy: -AnnotationStyle.stroke)
        case .erase(let r, _):
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
    case arrow, rectangle, text, highlight, blur, step, erase, cut
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
        }
    }

    /// 1…8 — number keys, so they never clash with letters used elsewhere.
    var key: Character { Character(String((Self.allCases.firstIndex(of: self) ?? 0) + 1)) }
}

/// The marks on one screenshot, with undo/redo and the tool/color in use.
@MainActor
@Observable
final class AnnotationDocument {
    private(set) var items: [Annotation] = []
    private var redoStack: [[Annotation]] = []
    private var undoStack: [[Annotation]] = []

    /// nil = no tool: the image can be dragged out to other apps.
    var tool: AnnotationTool?
    var color: AnnotationColor = .coral

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isEmpty: Bool { items.isEmpty }

    /// The next step badge number.
    var nextStep: Int {
        items.reduce(0) { if case .step(_, let n) = $1.kind { max($0, n) } else { $0 } } + 1
    }

    func add(_ kind: Annotation.Kind) {
        commit(items + [Annotation(kind: kind, color: color)])
    }

    func add(_ annotation: Annotation) {
        commit(items + [annotation])
    }

    /// Replaces one mark (e.g. a cut piece after it was moved) — one undo step.
    func update(_ id: Annotation.ID, to kind: Annotation.Kind) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var new = items
        new[i].kind = kind
        commit(new)
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(items)
        items = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(items)
        items = next
    }

    private func commit(_ new: [Annotation]) {
        undoStack.append(items)
        redoStack.removeAll()
        items = new
    }
}

/// Sizes shared by the live view and the export, in image points.
enum AnnotationStyle {
    static let stroke: CGFloat = 4
    static let arrowHead: CGFloat = 18
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
