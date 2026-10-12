import AppKit

/// Shotleaf's mark — selection corners with a spark inside — drawn in code.
/// The full-color app icon is generated from the same geometry by
/// scripts/make-icon.swift.
public enum BrandMark {
    /// Menu bar icon: a template image (macOS tints it for light/dark bars).
    public static let menuBarIcon: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let mark = rect.insetBy(dx: 1.5, dy: 1.5)
            NSColor.black.setStroke()
            let corners = Self.corners(in: mark, arm: 5)
            corners.lineWidth = 1.8
            corners.stroke()
            NSColor.black.setFill()
            spark(center: CGPoint(x: rect.midX, y: rect.midY), radius: 5.6).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    /// Top-left and bottom-right selection corners inside `rect` (y up).
    static func corners(in rect: CGRect, arm: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
        p.line(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.line(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY + arm))
        p.line(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.line(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
        return p
    }

    /// Four tips joined by soft concave curves.
    static func spark(center c: CGPoint, radius r: CGFloat) -> NSBezierPath {
        let tips = (0..<4).map { i -> CGPoint in
            let a = CGFloat(i) * .pi / 2 + .pi / 2
            return CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
        }
        let path = NSBezierPath()
        path.move(to: tips[0])
        for i in 0..<4 {
            let mid = CGFloat(i) * .pi / 2 + .pi / 2 + .pi / 4
            let pull = CGPoint(x: c.x + cos(mid) * r * 0.16, y: c.y + sin(mid) * r * 0.16)
            path.curve(to: tips[(i + 1) % 4], controlPoint1: pull, controlPoint2: pull)
        }
        path.close()
        return path
    }
}
