import CoreGraphics

/// Pure coordinate math for the region picker (unit-tested).
///
/// Three spaces meet here:
/// - **view**: one overlay per screen, points, origin top-left of that screen;
/// - **CG global**: what ScreenCaptureKit reports for windows — points, origin
///   top-left of the primary display;
/// - **image**: the frozen screenshot of one display, pixels, origin top-left.
enum CaptureGeometry {
    /// A rectangle spanned by two drag points, in any order.
    static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// CG-global rect → view rect of the screen whose CG-global frame is `screen`.
    static func viewRect(fromGlobal rect: CGRect, screen: CGRect) -> CGRect {
        rect.offsetBy(dx: -screen.minX, dy: -screen.minY)
    }

    /// View rect (points) → pixel rect in the frozen image, clamped to the image.
    static func pixelRect(fromView rect: CGRect, scale: CGFloat, imageSize: CGSize) -> CGRect {
        let pixels = CGRect(
            x: (rect.minX * scale).rounded(.down),
            y: (rect.minY * scale).rounded(.down),
            width: (rect.width * scale).rounded(.up),
            height: (rect.height * scale).rounded(.up)
        )
        return pixels.intersection(CGRect(origin: .zero, size: imageSize))
    }

    /// The topmost window containing `point` (windows ordered front to back).
    static func window(at point: CGPoint, in windows: [CGRect]) -> CGRect? {
        windows.first { $0.contains(point) }
    }

    /// Where the loupe goes: below-right of the cursor, flipped to stay on screen.
    static func loupeOrigin(cursor: CGPoint, loupe: CGSize, bounds: CGRect, gap: CGFloat = 24) -> CGPoint {
        var x = cursor.x + gap
        var y = cursor.y + gap
        if x + loupe.width > bounds.maxX { x = cursor.x - gap - loupe.width }
        if y + loupe.height > bounds.maxY { y = cursor.y - gap - loupe.height }
        return CGPoint(x: x, y: y)
    }
}
