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
        /// A callout: text on a bubble, with an optional tail pointing at `tail`.
        /// Lines wrap at `width` (nil = the default wrap).
        case text(origin: CGPoint, string: String, tail: CGPoint? = nil, width: CGFloat? = nil, size: CGFloat = AnnotationStyle.fontSize)
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
        /// Ruler: a line labelled with its length in screenshot pixels.
        case measure(from: CGPoint, to: CGPoint)
        /// Freehand line, as drawn.
        case pen([CGPoint])
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
        case .pen(let points):
            return points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }.insetBy(dx: -lineWidth, dy: -lineWidth)
        case .measure(let a, let b):
            return CaptureMath.rect(a, b).insetBy(dx: -40, dy: -24) // room for the label
        case .highlight(let r), .blur(let r):
            return r
        case .erase(let r, _), .focus(let r):
            return r
        case .piece(let source, let offset, _):
            return source.union(source.offsetBy(dx: offset.width, dy: offset.height))
        case .step(let c, _):
            let r = AnnotationStyle.stepRadius
            return CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        case .text(let o, let s, let tail, let w, let f):
            let bubble = AnnotationStyle.bubble(origin: o, string: s, width: w, size: f)
            return tail.map { bubble.union(CGRect(origin: $0, size: .zero)).insetBy(dx: -2, dy: -2) } ?? bubble
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

    /// Badge colors for steps (white badges would vanish on light shots).
    static let stepCycle: [AnnotationColor] = [.coral, .amber, .leaf, .sky, .ink]

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
    case arrow, rectangle, text, highlight, pen, blur, step, erase, cut, focus, ellipse, crop, ruler
    var id: String { rawValue }

    /// The tools on 1…9, in their original order (kept stable for muscle memory).
    private static let numbered: [AnnotationTool] = [.arrow, .rectangle, .text, .highlight, .blur, .step, .erase, .cut, .focus]

    var title: String {
        switch self {
        case .arrow: String(localized: "Arrow")
        case .rectangle: String(localized: "Box")
        case .text: String(localized: "Text")
        case .highlight: String(localized: "Marker")
        case .pen: String(localized: "Pen")
        case .blur: String(localized: "Blur")
        case .step: String(localized: "Steps")
        case .erase: String(localized: "Erase")
        case .cut: String(localized: "Cut")
        case .focus: String(localized: "Focus")
        case .ellipse: String(localized: "Oval")
        case .crop: String(localized: "Crop")
        case .ruler: String(localized: "Ruler")
        }
    }

    /// Tools whose marks have a line thickness.
    var usesLineWidth: Bool { [.arrow, .rectangle, .ellipse, .pen].contains(self) }

    /// The editor key: the user's own (Settings → Editor tools) or the
    /// default — 1…9 for the original tools, letters for later ones. None of
    /// them may be P / T / 0, which the editor uses itself. nil = no key.
    var key: Character? {
        if let custom = ToolPrefs.keys[rawValue] { return custom.first }
        return defaultKey
    }

    var defaultKey: Character {
        switch self {
        case .ellipse: "o"
        case .crop: "c"
        case .ruler: "m"
        case .pen: "d"
        default: Character(String((Self.numbered.firstIndex(of: self) ?? 0) + 1))
        }
    }

    /// The toolbar order: the user's, with any tool it lacks at the end.
    static var ordered: [AnnotationTool] {
        let saved = ToolPrefs.order.compactMap(AnnotationTool.init(rawValue:))
        return saved + allCases.filter { !saved.contains($0) }
    }

    /// "  D" for tooltips and menus ("" without a key).
    var keyLabel: String { key.map { String($0).uppercased() } ?? "" }
}

/// The user's editor tool keys and order, in UserDefaults.
enum ToolPrefs {
    /// Keys the editor keeps for itself.
    static let reserved: Set<Character> = ["p", "t", "0", " "]

    /// tool → key ("" = no key); missing = the default.
    static var keys: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "toolKeys") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "toolKeys") }
    }

    static var order: [String] {
        get { UserDefaults.standard.stringArray(forKey: "toolOrder") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "toolOrder") }
    }

    /// Gives `tool` the key `typed` (its last letter or digit; empty = none).
    /// A tool already on that key loses it. Reserved keys are refused (false).
    @discardableResult
    static func setKey(_ typed: String, for tool: AnnotationTool) -> Bool {
        let key = typed.lowercased().last.map(String.init) ?? ""
        if let k = key.first, reserved.contains(k) { return false }
        var all = keys
        if !key.isEmpty {
            for other in AnnotationTool.allCases where other != tool && other.key.map(String.init) == key { all[other.rawValue] = "" }
        }
        all[tool.rawValue] = key == String(tool.defaultKey) ? nil : key
        keys = all
        return true
    }

    static func move(_ tool: AnnotationTool, by offset: Int) {
        var list = AnnotationTool.ordered
        guard let i = list.firstIndex(of: tool), list.indices.contains(i + offset) else { return }
        list.swapAt(i, i + offset)
        order = list.map(\.rawValue)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: "toolKeys")
        UserDefaults.standard.removeObject(forKey: "toolOrder")
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
        /// After "Remove background": transparent around the subject.
        var cutOut = false
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

    /// "Фон" around the result (nil = none).
    var backdrop: Backdrop?
    /// Stamped on the result; starts as the last one used.
    var watermark: Watermark? = Watermark.saved

    /// nil = Select: click a mark to select, move, resize or delete it.
    var tool: AnnotationTool?
    var color: AnnotationColor = .coral
    var lineWidth: CGFloat = AnnotationStyle.stroke
    /// Font size for new callouts.
    var fontSize: CGFloat = AnnotationStyle.fontSize
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
    /// replaces the old one. Steps take turns through the palette, starting
    /// at the current color, so each badge stands out from the last.
    @discardableResult
    func add(_ kind: Annotation.Kind) -> Annotation.ID {
        var markColor = color
        if case .step(_, let n) = kind {
            let cycle = AnnotationColor.stepCycle
            markColor = cycle[((cycle.firstIndex(of: color) ?? 0) + n - 1) % cycle.count]
        }
        let item = Annotation(kind: kind, color: markColor, lineWidth: lineWidth)
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
        base = Base(image: cropped, size: area.size, cutOut: current.cutOut)
        selection = nil
    }

    /// A new picture of the same size under the marks ("Remove background") — one undo step.
    func replacePicture(_ image: CGImage, size: CGSize, cutOut: Bool) {
        undoStack.append(Snapshot(items: items, base: base))
        redoStack.removeAll()
        base = Base(image: image, size: size, cutOut: cutOut)
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

    /// Callout text wraps here unless its width was dragged.
    static let textWrap: CGFloat = 320
    static let minTextWidth: CGFloat = 40

    /// The wrapped text's size (`width` nil = `textWrap`).
    /// Callout font sizes on offer, and the default.
    static let fontSizes: [CGFloat] = [14, 18, 22, 28, 36, 48]
    static let fontSize: CGFloat = 22

    static func textSize(_ string: String, width: CGFloat?, size: CGFloat) -> CGSize {
        let r = NSAttributedString(string: string, attributes: textAttributes(color: .black, size: size))
            .boundingRect(with: CGSize(width: width ?? textWrap, height: .greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading])
        return CGSize(width: ceil(r.width), height: ceil(r.height))
    }

    /// The callout bubble around a text mark (text starts at `origin`).
    static func bubble(origin: CGPoint, string: String, width: CGFloat?, size: CGFloat) -> CGRect {
        CGRect(origin: origin, size: textSize(string, width: width, size: size)).insetBy(dx: -10, dy: -5)
    }

    /// Where a new callout's tail points: down-left of the bubble.
    static func defaultTail(origin: CGPoint, string: String, size: CGFloat) -> CGPoint {
        let b = bubble(origin: origin, string: string, width: nil, size: size)
        return CGPoint(x: b.minX - 28, y: b.maxY + 40)
    }

    static func textAttributes(color: NSColor, size: CGFloat = fontSize) -> [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        let font = NSFont.systemFont(ofSize: size, weight: .bold)
        let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? font
        return [.font: rounded, .foregroundColor: color, .shadow: shadow]
    }
}
