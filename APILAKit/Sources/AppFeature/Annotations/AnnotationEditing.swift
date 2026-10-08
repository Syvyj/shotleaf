import CoreGraphics

/// Pure geometry for selecting and editing marks (unit-tested): what's under
/// the pointer, where the handles are, and how a drag moves or resizes a mark.
enum AnnotationEditing {
    /// A grab point on a selected mark.
    enum Handle: Equatable {
        case arrowStart, arrowEnd
        case corner(Int) // 0 top-left, 1 top-right, 2 bottom-right, 3 bottom-left
    }

    /// How close (in image points) a click must be to count as on a line/handle.
    static let tolerance: CGFloat = 8

    /// The topmost mark under `p`.
    static func hit(_ items: [Annotation], at p: CGPoint) -> Annotation.ID? {
        items.reversed().first { contains($0.kind, p) }?.id
    }

    static func contains(_ kind: Annotation.Kind, _ p: CGPoint) -> Bool {
        switch kind {
        case .arrow(let a, let b): return distance(from: p, toSegment: a, b) <= tolerance
        case .rectangle(let r), .highlight(let r), .blur(let r), .erase(let r, _), .focus(let r):
            return r.insetBy(dx: -tolerance / 2, dy: -tolerance / 2).contains(p)
        case .piece(let source, let offset, _):
            return source.offsetBy(dx: offset.width, dy: offset.height).contains(p)
        case .step(let c, _):
            return hypot(p.x - c.x, p.y - c.y) <= AnnotationStyle.stepRadius + tolerance / 2
        case .text:
            return Annotation(kind: kind, color: .coral).bounds.contains(p)
        }
    }

    /// The box a selection outline is drawn around.
    static func frame(of kind: Annotation.Kind) -> CGRect {
        switch kind {
        case .arrow(let a, let b): return CaptureMath.rect(a, b)
        case .rectangle(let r), .highlight(let r), .blur(let r), .erase(let r, _), .focus(let r): return r
        case .piece(let source, let offset, _): return source.offsetBy(dx: offset.width, dy: offset.height)
        default: return Annotation(kind: kind, color: .coral).bounds
        }
    }

    /// Handles a mark offers: arrow ends, or the four corners of area marks.
    /// Steps, text and cut pieces only move.
    static func handles(of kind: Annotation.Kind) -> [(Handle, CGPoint)] {
        switch kind {
        case .arrow(let a, let b):
            return [(.arrowStart, a), (.arrowEnd, b)]
        case .rectangle(let r), .highlight(let r), .blur(let r), .erase(let r, _), .focus(let r):
            return [(.corner(0), CGPoint(x: r.minX, y: r.minY)), (.corner(1), CGPoint(x: r.maxX, y: r.minY)),
                    (.corner(2), CGPoint(x: r.maxX, y: r.maxY)), (.corner(3), CGPoint(x: r.minX, y: r.maxY))]
        default:
            return []
        }
    }

    static func handle(of kind: Annotation.Kind, at p: CGPoint) -> Handle? {
        handles(of: kind).first { hypot($0.1.x - p.x, $0.1.y - p.y) <= tolerance }?.0
    }

    /// The mark shifted by `d`. A cut piece moves (its hole stays); erase keeps
    /// its sampled color.
    static func moved(_ kind: Annotation.Kind, by d: CGSize) -> Annotation.Kind {
        func m(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + d.width, y: p.y + d.height) }
        func m(_ r: CGRect) -> CGRect { r.offsetBy(dx: d.width, dy: d.height) }
        switch kind {
        case .arrow(let a, let b): return .arrow(from: m(a), to: m(b))
        case .rectangle(let r): return .rectangle(m(r))
        case .highlight(let r): return .highlight(m(r))
        case .blur(let r): return .blur(m(r))
        case .focus(let r): return .focus(m(r))
        case .erase(let r, let fill): return .erase(m(r), fill: fill)
        case .step(let c, let n): return .step(center: m(c), number: n)
        case .text(let o, let s): return .text(origin: m(o), string: s)
        case .piece(let source, let offset, let fill):
            return .piece(source: source, offset: CGSize(width: offset.width + d.width, height: offset.height + d.height), fill: fill)
        }
    }

    /// The mark with `handle` dragged to `p`. Corners keep the opposite corner
    /// fixed; dragging past it flips the box instead of inverting it.
    static func resized(_ kind: Annotation.Kind, _ handle: Handle, to p: CGPoint) -> Annotation.Kind {
        func box(_ r: CGRect) -> CGRect {
            guard case .corner(let i) = handle else { return r }
            let opposite = [CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY),
                            CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY)][i]
            return CaptureMath.rect(opposite, p)
        }
        switch (kind, handle) {
        case (.arrow(_, let b), .arrowStart): return .arrow(from: p, to: b)
        case (.arrow(let a, _), .arrowEnd): return .arrow(from: a, to: p)
        case (.rectangle(let r), _): return .rectangle(box(r))
        case (.highlight(let r), _): return .highlight(box(r))
        case (.blur(let r), _): return .blur(box(r))
        case (.focus(let r), _): return .focus(box(r))
        case (.erase(let r, let fill), _): return .erase(box(r), fill: fill)
        default: return kind
        }
    }

    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
