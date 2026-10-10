import AppKit

/// A text or picture stamped on the result: one of 9 spots, its width a share
/// of the picture's, see-through and optionally tilted. The last one used is
/// remembered for the next shots.
struct Watermark: Codable, Equatable {
    enum Kind: String, Codable { case text, image }

    var kind: Kind = .text
    var text = "APILA"
    var imagePath: String?
    /// 0…8, row by row from the top-left; 8 = bottom-right.
    var position = 8
    /// Width as a share of the picture's width.
    var size: CGFloat = 0.22
    var opacity: CGFloat = 0.6
    /// Degrees, clockwise.
    var rotation: CGFloat = 0

    static let sizeRange: ClosedRange<CGFloat> = 0.05...0.8
    static let opacityRange: ClosedRange<CGFloat> = 0.1...1
    static let rotationRange: ClosedRange<CGFloat> = -45...45

    /// The watermark new shots start with (nil = none).
    static var saved: Watermark? {
        get { UserDefaults.standard.data(forKey: "watermark").flatMap { try? JSONDecoder().decode(Watermark.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "watermark") }
    }

    private var image: NSImage? { imagePath.flatMap(NSImage.init(contentsOfFile:)) }

    /// Draws into a flipped (y-down) context over `area`, in image points.
    func draw(in ctx: CGContext, area: CGRect) {
        let width = area.width * size
        var mark: (size: CGSize, draw: (CGRect) -> Void)?
        switch kind {
        case .text:
            let string = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !string.isEmpty else { return }
            let probe = NSAttributedString(string: string, attributes: Self.attributes(100)).size()
            let attributed = NSAttributedString(string: string, attributes: Self.attributes(100 * width / max(probe.width, 1)))
            mark = (attributed.size(), { rect in attributed.draw(at: rect.origin) })
        case .image:
            guard let image, image.size.width > 0 else { return }
            let size = CGSize(width: width, height: width * image.size.height / image.size.width)
            mark = (size, { rect in image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) })
        }
        guard let mark else { return }
        let margin = min(area.width, area.height) * 0.04
        let column = position % 3, row = position / 3
        let x = [area.minX + margin, area.midX - mark.size.width / 2, area.maxX - margin - mark.size.width][column]
        let y = [area.minY + margin, area.midY - mark.size.height / 2, area.maxY - margin - mark.size.height][row]
        let rect = CGRect(origin: CGPoint(x: x, y: y), size: mark.size)

        ctx.saveGState()
        ctx.translateBy(x: rect.midX, y: rect.midY)
        ctx.rotate(by: rotation * .pi / 180)
        ctx.translateBy(x: -rect.midX, y: -rect.midY)
        ctx.setAlpha(opacity)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil) // one see-through layer, so the shadow doesn't show through the text
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        mark.draw(rect)
        NSGraphicsContext.restoreGraphicsState()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// White bold rounded type with a soft dark shadow: readable on any picture.
    private static func attributes(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = max(1, size * 0.08)
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.02)
        let font = NSFont.systemFont(ofSize: size, weight: .bold)
        let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? font
        return [.font: rounded, .foregroundColor: NSColor.white, .shadow: shadow]
    }
}
