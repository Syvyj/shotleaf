import AppKit

/// APILA's own look for the capture overlay: a violet → cyan accent, soft glass
/// capsules, rounded type. No system "screenshot" iconography.
enum CaptureStyle {
    static let violet = NSColor(srgbRed: 0.55, green: 0.36, blue: 1.00, alpha: 1)
    static let cyan = NSColor(srgbRed: 0.20, green: 0.84, blue: 0.95, alpha: 1)
    static var accentGradient: NSGradient { NSGradient(starting: violet, ending: cyan)! }

    /// Outside the selection.
    static let dim = NSColor(white: 0.04, alpha: 0.48)
    /// Glass capsule behind labels and hints.
    static let capsule = NSColor(white: 0.08, alpha: 0.78)
    static let capsuleStroke = NSColor(white: 1, alpha: 0.10)
    static let keycap = NSColor(white: 1, alpha: 0.14)

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
}
