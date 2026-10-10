import AppKit

/// Draws annotations with Core Graphics — used both live (SwiftUI Canvas) and
/// for export, so the saved image is exactly what was on screen.
/// All drawing is in image points with y pointing down (a flipped context).
enum AnnotationRenderer {
    /// - Parameters:
    ///   - image: the original screenshot (needed to pixelate under Blur).
    ///   - imageSize: the screenshot's size in image points.
    /// - Parameter cropGuide: dim and outline what a crop will cut away (on
    ///   screen only — the export simply leaves it out).
    static func draw(_ items: [Annotation], image: CGImage, imageSize: CGSize, in ctx: CGContext, cropGuide: Bool = true) {
        // Three layers: marks that change the picture itself (blur, erase, cut
        // pieces), then the focus dimming over that picture, then the marks
        // drawn on top of it (arrows, boxes, text…), which must never be dimmed.
        func changesPicture(_ k: Annotation.Kind) -> Bool {
            switch k { case .blur, .erase, .piece: true; default: false }
        }
        drawEach(items.filter { changesPicture($0.kind) }, image: image, imageSize: imageSize, in: ctx)
        let spots = items.compactMap { if case .focus(let r) = $0.kind { r } else { nil } }
        if !spots.isEmpty { focus(spots, imageSize: imageSize, in: ctx) }
        drawEach(items.filter { !changesPicture($0.kind) }, image: image, imageSize: imageSize, in: ctx)
        if cropGuide, let crop = items.lazy.compactMap({ if case .crop(let r) = $0.kind { r } else { nil } }).first {
            cropGuideLayer(crop, in: ctx)
        }
    }

    /// Everything outside the crop gets a heavy veil and the edge a dashed line.
    private static func cropGuideLayer(_ r: CGRect, in ctx: CGContext) {
        ctx.saveGState()
        ctx.addRect(r.insetBy(dx: -10_000, dy: -10_000))
        ctx.addRect(r)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        ctx.fillPath(using: .evenOdd)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.stroke(r)
        ctx.restoreGState()
    }

    private static func drawEach(_ items: [Annotation], image: CGImage, imageSize: CGSize, in ctx: CGContext) {
        for item in items {
            ctx.saveGState()
            let color = item.color.nsColor.cgColor
            switch item.kind {
            case .arrow(let a, let b): arrow(from: a, to: b, width: item.lineWidth, color: color, in: ctx)
            case .measure(let a, let b):
                measure(from: a, to: b, pixelsPerPoint: CGFloat(image.width) / max(imageSize.width, 1), color: item.color.nsColor, in: ctx)
            case .rectangle(let r): box(r, width: item.lineWidth, color: color, in: ctx)
            case .pen(let points): pen(points, width: item.lineWidth, color: color, in: ctx)
            case .focus, .crop: break // focus drawn above; crop is a guide / export bound
            case .ellipse(let r):
                softShadow(ctx)
                ctx.setStrokeColor(color)
                ctx.setLineWidth(item.lineWidth)
                ctx.strokeEllipse(in: r)
            case .highlight(let r): highlight(r, color: color, in: ctx)
            case .blur(let r): pixelate(r, image: image, imageSize: imageSize, in: ctx)
            case .step(let c, let n): step(c, number: n, color: item.color.nsColor, in: ctx)
            case .text(let o, let s, let tail, let w, let f): callout(s, at: o, tail: tail, width: w, size: f, color: item.color.nsColor, in: ctx)
            case .erase(let r, let fill): erase(r, fill: fill, imageSize: imageSize, in: ctx)
            case .piece(let source, let offset, let fill):
                erase(source, fill: fill, imageSize: imageSize, in: ctx)
                piece(source, offset: offset, image: image, imageSize: imageSize, in: ctx)
            }
            ctx.restoreGState()
        }
    }

    // MARK: Marks

    private static func softShadow(_ ctx: CGContext) {
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    }

    private static func arrow(from a: CGPoint, to b: CGPoint, width: CGFloat, color: CGColor, in ctx: CGContext) {
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 2 else { return }
        let angle = atan2(b.y - a.y, b.x - a.x)
        let head = min(AnnotationStyle.arrowHead(for: width), length * 0.6)
        // Shaft stops inside the head so the tip stays sharp.
        let shaftEnd = CGPoint(x: b.x - cos(angle) * head * 0.6, y: b.y - sin(angle) * head * 0.6)
        softShadow(ctx)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.move(to: a)
        ctx.addLine(to: shaftEnd)
        ctx.strokePath()
        let spread: CGFloat = .pi / 7
        ctx.setFillColor(color)
        ctx.move(to: b)
        ctx.addLine(to: CGPoint(x: b.x - cos(angle - spread) * head, y: b.y - sin(angle - spread) * head))
        ctx.addLine(to: CGPoint(x: b.x - cos(angle + spread) * head, y: b.y - sin(angle + spread) * head))
        ctx.closePath()
        ctx.fillPath()
    }

    private static func box(_ r: CGRect, width: CGFloat, color: CGColor, in ctx: CGContext) {
        softShadow(ctx)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 4, cornerHeight: 4, transform: nil))
        ctx.strokePath()
    }

    /// Smooth freehand line: curves through the midpoints between samples.
    private static func pen(_ points: [CGPoint], width: CGFloat, color: CGColor, in ctx: CGContext) {
        guard let first = points.first else { return }
        softShadow(ctx)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: first)
        for (a, b) in zip(points.dropFirst(), points.dropFirst(2)) {
            ctx.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
        }
        ctx.addLine(to: points.last!)
        ctx.strokePath()
    }

    private static func highlight(_ r: CGRect, color: CGColor, in ctx: CGContext) {
        ctx.setBlendMode(.multiply)
        ctx.setFillColor(color.copy(alpha: 0.45) ?? color)
        ctx.fill(r)
    }

    /// Pixelates the image under `r` (the part inside the image).
    private static func pixelate(_ r: CGRect, image: CGImage, imageSize: CGSize, in ctx: CGContext) {
        let area = r.intersection(CGRect(origin: .zero, size: imageSize))
        guard !area.isEmpty else { return }
        let scale = CGFloat(image.width) / imageSize.width
        let pixels = CGRect(x: area.minX * scale, y: area.minY * scale, width: area.width * scale, height: area.height * scale).integral
        guard let crop = image.cropping(to: pixels) else { return }
        let cells = CGSize(width: max(1, (area.width / AnnotationStyle.blurBlock).rounded()),
                           height: max(1, (area.height / AnnotationStyle.blurBlock).rounded()))
        guard let small = CGContext(data: nil, width: Int(cells.width), height: Int(cells.height), bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        small.interpolationQuality = .medium
        small.draw(crop, in: CGRect(origin: .zero, size: cells))
        guard let tiny = small.makeImage() else { return }
        ctx.interpolationQuality = .none
        drawUpright(tiny, in: area, ctx: ctx)
    }

    private static func step(_ c: CGPoint, number: Int, color: NSColor, in ctx: CGContext) {
        let r = AnnotationStyle.stepRadius
        let circle = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        softShadow(ctx)
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: circle)
        ctx.setShadow(offset: .zero, blur: 0)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: circle.insetBy(dx: 1, dy: 1))
        let label = NSAttributedString(string: "\(number)", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .heavy),
            .foregroundColor: color == AnnotationColor.white.nsColor ? NSColor.black : NSColor.white,
        ])
        let size = label.size()
        drawText(label, at: CGPoint(x: c.x - size.width / 2, y: c.y - size.height / 2), in: ctx)
    }

    /// A thin line with end ticks and its length in pixels on a pill.
    private static func measure(from a: CGPoint, to b: CGPoint, pixelsPerPoint: CGFloat, color: NSColor, in ctx: CGContext) {
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 1 else { return }
        let n = CGPoint(x: -(b.y - a.y) / length * 7, y: (b.x - a.x) / length * 7) // tick half-length, across the line
        ctx.saveGState()
        softShadow(ctx)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(2)
        ctx.setLineCap(.round)
        for p in [a, b] {
            ctx.move(to: CGPoint(x: p.x - n.x, y: p.y - n.y))
            ctx.addLine(to: CGPoint(x: p.x + n.x, y: p.y + n.y))
        }
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
        ctx.restoreGState()

        let light = [AnnotationColor.white, .amber].map(\.nsColor).contains(color)
        let label = NSAttributedString(string: "\(Int((length * pixelsPerPoint).rounded())) px", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: light ? NSColor.black : NSColor.white,
        ])
        let size = label.size()
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let pill = CGRect(x: mid.x - size.width / 2 - 7, y: mid.y - size.height / 2 - 3, width: size.width + 14, height: size.height + 6)
        ctx.setFillColor(color.cgColor)
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: pill.height / 2, cornerHeight: pill.height / 2, transform: nil))
        ctx.fillPath()
        drawText(label, at: CGPoint(x: pill.minX + 7, y: pill.minY + 3), in: ctx)
    }

    /// A bubble in the mark's color with the text on it, and a tapering tail
    /// from the bubble's middle to `tail` (the bubble hides its root).
    private static func callout(_ s: String, at o: CGPoint, tail: CGPoint?, width: CGFloat?, size: CGFloat,
                                color: NSColor, in ctx: CGContext) {
        let bubble = AnnotationStyle.bubble(origin: o, string: s, width: width, size: size)
        ctx.saveGState()
        softShadow(ctx)
        ctx.setFillColor(color.cgColor)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil) // one shadow for bubble + tail
        if let tail {
            let c = CGPoint(x: bubble.midX, y: bubble.midY)
            let angle = atan2(tail.y - c.y, tail.x - c.x) + .pi / 2
            let half = min(12, bubble.height / 2 - 2)
            ctx.move(to: CGPoint(x: c.x + cos(angle) * half, y: c.y + sin(angle) * half))
            ctx.addLine(to: tail)
            ctx.addLine(to: CGPoint(x: c.x - cos(angle) * half, y: c.y - sin(angle) * half))
            ctx.closePath()
            ctx.fillPath()
        }
        ctx.addPath(CGPath(roundedRect: bubble, cornerWidth: 9, cornerHeight: 9, transform: nil))
        ctx.fillPath()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
        let light = [AnnotationColor.white, .amber].map(\.nsColor).contains(color)
        var attributes = AnnotationStyle.textAttributes(color: light ? .black : .white, size: size)
        attributes[.shadow] = nil
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSAttributedString(string: s, attributes: attributes)
            .draw(with: bubble.insetBy(dx: 10, dy: 5), options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Dims the image outside the focus areas, and rims them with a soft light.
    /// ponytail: overlapping focus areas cancel out (even-odd); merge if it matters.
    private static func focus(_ spots: [CGRect], imageSize: CGSize, in ctx: CGContext) {
        ctx.saveGState()
        ctx.addRect(CGRect(origin: .zero, size: imageSize))
        for r in spots { ctx.addPath(CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil)) }
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.fillPath(using: .evenOdd)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(1.5)
        for r in spots { ctx.addPath(CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil)) }
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Erasing only touches the image (the canvas around it is already plain).
    private static func erase(_ r: CGRect, fill: NSColor, imageSize: CGSize, in ctx: CGContext) {
        let area = r.intersection(CGRect(origin: .zero, size: imageSize))
        guard !area.isEmpty else { return }
        ctx.setFillColor(fill.cgColor)
        ctx.fill(area)
    }

    private static func piece(_ source: CGRect, offset: CGSize, image: CGImage, imageSize: CGSize, in ctx: CGContext) {
        let area = source.intersection(CGRect(origin: .zero, size: imageSize))
        let scale = CGFloat(image.width) / imageSize.width
        let pixels = CGRect(x: area.minX * scale, y: area.minY * scale, width: area.width * scale, height: area.height * scale).integral
        guard !area.isEmpty, let crop = image.cropping(to: pixels) else { return }
        let target = area.offsetBy(dx: offset.width, dy: offset.height)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 8, color: NSColor.black.withAlphaComponent(0.30).cgColor)
        drawUpright(crop, in: target, ctx: ctx)
        ctx.restoreGState()
    }

    /// The color around `r` in the image — the median of the pixels on its
    /// border, so a few letters touching the edge don't tint it.
    static func surroundingColor(of r: CGRect, image: CGImage, imageSize: CGSize) -> NSColor {
        let scale = CGFloat(image.width) / imageSize.width
        let px = CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale)
            .insetBy(dx: -2, dy: -2).integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard px.width >= 2, px.height >= 2, let crop = image.cropping(to: px) else { return .white }
        let w = crop.width, h = crop.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return .white }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        var r8: [UInt8] = [], g8: [UInt8] = [], b8: [UInt8] = []
        func take(_ x: Int, _ y: Int) {
            let i = (y * w + x) * 4
            r8.append(data[i]); g8.append(data[i + 1]); b8.append(data[i + 2])
        }
        for x in 0..<w { take(x, 0); take(x, h - 1) }
        for y in 1..<(h - 1) { take(0, y); take(w - 1, y) }
        func median(_ v: [UInt8]) -> CGFloat { CGFloat(v.sorted()[v.count / 2]) / 255 }
        return NSColor(srgbRed: median(r8), green: median(g8), blue: median(b8), alpha: 1)
    }

    // MARK: Helpers (the context is flipped: y down)

    private static func drawText(_ text: NSAttributedString, at p: CGPoint, in ctx: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        text.draw(at: p)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// CGContext.draw puts images upside down in a flipped context.
    static func drawUpright(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    // MARK: Export

    /// The area to export, in image points: the image, grown to include any
    /// marks drawn on the canvas around it (plus a little margin).
    static func exportBounds(_ items: [Annotation], imageSize: CGSize) -> CGRect {
        if let crop = items.lazy.compactMap({ if case .crop(let r) = $0.kind { r } else { nil } }).first {
            return crop.integral
        }
        let image = CGRect(origin: .zero, size: imageSize)
        let marks = items.reduce(CGRect.null) { $0.union($1.bounds) }
        guard !marks.isNull, !image.contains(marks) else { return image }
        return image.union(marks.insetBy(dx: -16, dy: -16)).integral
    }

    /// The screenshot with its marks, at the original pixel density. Canvas
    /// area outside the image is filled with `canvas`.
    static func export(_ image: CGImage, imageSize: CGSize, items: [Annotation], canvas: NSColor = .white,
                       watermark: Watermark? = nil) -> CGImage? {
        guard !items.isEmpty || watermark != nil else { return image }
        let bounds = exportBounds(items, imageSize: imageSize)
        let scale = CGFloat(image.width) / imageSize.width
        guard let ctx = CGContext(data: nil, width: Int((bounds.width * scale).rounded()), height: Int((bounds.height * scale).rounded()),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Flip to y-down image points.
        ctx.translateBy(x: 0, y: CGFloat(ctx.height))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
        ctx.setFillColor(canvas.cgColor)
        ctx.fill(bounds)
        ctx.interpolationQuality = .high
        drawUpright(image, in: CGRect(origin: .zero, size: imageSize), ctx: ctx)
        draw(items, image: image, imageSize: imageSize, in: ctx, cropGuide: false)
        watermark?.draw(in: ctx, area: bounds)
        return ctx.makeImage()
    }
}
