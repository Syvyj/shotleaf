import AppKit

/// Shotleaf's own look for the capture overlay — the "Leaves" palette (fresh green
/// → lime), soft glass capsules, rounded type. No system screenshot iconography.
enum CaptureStyle {
    static let leaf = NSColor(srgbRed: 0x8F / 255.0, green: 0xBF / 255.0, blue: 0x3A / 255.0, alpha: 1)
    static let lime = NSColor(srgbRed: 0xC9 / 255.0, green: 0xE8 / 255.0, blue: 0x6A / 255.0, alpha: 1)
    static var accentGradient: NSGradient { NSGradient(starting: leaf, ending: lime)! }

    /// Outside the selection.
    static let dim = NSColor(white: 0.04, alpha: 0.48)
    /// Glass capsule behind labels and hints.
    static let capsule = NSColor(srgbRed: 0x12 / 255.0, green: 0x1A / 255.0, blue: 0x12 / 255.0, alpha: 0.82)
    /// The windows' light panel (hint bar).
    static let panel = NSColor(srgbRed: 0.97, green: 0.98, blue: 0.96, alpha: 0.96)
    static let forest = NSColor(srgbRed: 0x12 / 255.0, green: 0x1A / 255.0, blue: 0x12 / 255.0, alpha: 1)
    static let capsuleStroke = NSColor(white: 1, alpha: 0.10)

    static let selectionRadius: CGFloat = 6

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .medium) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: rounded, size: size) ?? base
    }

    static func mono(_ size: CGFloat) -> NSFont {
        .monospacedDigitSystemFont(ofSize: size, weight: .semibold)
    }

    /// Text attributes for overlay labels.
    static func label(_ font: NSFont, color: NSColor = .white) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: color]
    }

    /// The selection's frame: soft lime glow, then the gradient ring just outside `rect`.
    static func drawFrame(_ rect: CGRect, ringWidth: CGFloat) {
        let r = CaptureStyle.selectionRadius
        let outline = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = CaptureStyle.lime.withAlphaComponent(0.7)
        glow.shadowBlurRadius = 14
        glow.set()
        CaptureStyle.leaf.withAlphaComponent(0.6).setStroke()
        outline.lineWidth = 2
        outline.stroke()
        NSGraphicsContext.restoreGraphicsState()

        let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: r + 1, yRadius: r + 1)
        ring.lineWidth = ringWidth
        NSGraphicsContext.saveGraphicsState()
        let strokeArea = NSBezierPath(roundedRect: rect.insetBy(dx: -2, dy: -2), xRadius: r + 2, yRadius: r + 2)
        strokeArea.append(NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: r, yRadius: r))
        strokeArea.windingRule = .evenOdd
        strokeArea.addClip()
        CaptureStyle.accentGradient.draw(in: ring.bounds.insetBy(dx: -2, dy: -2), angle: -30)
        NSGraphicsContext.restoreGraphicsState()
    }
}
