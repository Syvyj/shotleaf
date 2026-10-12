import AppKit

/// One screen of the region picker: shows the frozen screenshot and lets the
/// user drag a region, click a window, or use the keyboard. Top-left origin
/// (flipped) so view points map straight onto image pixels.
final class SelectionView: NSView {
    enum Outcome {
        /// View points; `scrolling`: film it while the user scrolls.
        case region(CGRect, scrolling: Bool)
        case cancel
        case repeatLast
    }

    private let image: CGImage
    private let nsImage: NSImage
    private let scale: CGFloat
    /// Windows on this screen, front to back, in view points.
    private let windows: [CGRect]
    private let canRepeat: Bool
    private let finish: (Outcome) -> Void

    var dragStart: CGPoint?  // internal: state is set directly by the preview render test
    var selection: CGRect?
    var cursor: CGPoint?
    var hoveredWindow: CGRect?
    /// S toggles: the next region becomes a scrolling screenshot.
    var scrolling = false

    init(frame: CGRect, image: CGImage, scale: CGFloat, windows: [CGRect], canRepeat: Bool, finish: @escaping (Outcome) -> Void) {
        self.image = image
        self.nsImage = NSImage(cgImage: image, size: frame.size)
        self.scale = scale
        self.windows = windows
        self.canRepeat = canRepeat
        self.finish = finish
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    // MARK: Mouse

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    /// Cursor rects only apply while APILA is the active app, and the picker
    /// deliberately doesn't activate it — so set the crosshair on every move.
    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        cursor = point(event)
        hoveredWindow = CaptureGeometry.window(at: cursor!, in: windows)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        cursor = nil
        hoveredWindow = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = point(event)
        selection = nil
    }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.crosshair.set()
        guard let dragStart else { return }
        cursor = point(event)
        selection = CaptureGeometry.rect(from: dragStart, to: cursor!).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        if let selection, selection.width >= 4, selection.height >= 4 {
            finish(.region(selection, scrolling: scrolling))
        } else {
            // A click (no real drag): the window under the cursor, or the whole screen.
            finish(.region(hoveredWindow?.intersection(bounds) ?? bounds, scrolling: scrolling))
        }
    }

    override func rightMouseDown(with event: NSEvent) { finish(.cancel) }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        switch (event.keyCode, event.charactersIgnoringModifiers?.lowercased()) {
        case (53, _): finish(.cancel)                       // Esc
        case (36, _), (76, _), (_, "f"): finish(.region(bounds, scrolling: scrolling)) // Return / Enter / F
        case (_, "r") where canRepeat: finish(.repeatLast)
        case (_, "s"):
            scrolling.toggle()
            needsDisplay = true
        case (_, "c"):                                      // eyedropper: copy the HEX under the cursor
            guard let cursor else { return }
            let hex = pixelHex(x: Int((cursor.x * scale).rounded(.down)), y: Int((cursor.y * scale).rounded(.down)))
            guard hex.hasPrefix("#") else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
            finish(.cancel)
        default: super.keyDown(with: event)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        nsImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])

        let focus = selection ?? (dragStart == nil ? hoveredWindow : nil)
        drawDim(except: focus)
        if let focus { drawFrame(focus, isWindow: selection == nil) }
        if let selection { drawSizeLabel(for: selection) }
        if let cursor {
            if selection == nil { drawCrosshair(at: cursor) }
            drawLoupe(at: cursor)
        }
        drawHints()
        if scrolling { drawScrollingBanner() }
    }

    /// Top banner while S is on, so the mode is hard to miss.
    private func drawScrollingBanner() {
        let text = NSAttributedString(string: String(localized: "Scrolling screenshot — pick an area, then scroll"),
                                      attributes: CaptureStyle.label(CaptureStyle.font(13, .semibold)))
        let size = text.size()
        let box = CGRect(x: bounds.midX - size.width / 2 - 18, y: 28, width: size.width + 36, height: 34)
        drawCapsule(box)
        text.draw(at: CGPoint(x: box.minX + 18, y: box.midY - size.height / 2))
    }

    private func drawDim(except hole: CGRect?) {
        let path = NSBezierPath(rect: bounds)
        if let hole {
            path.append(NSBezierPath(roundedRect: hole, xRadius: CaptureStyle.selectionRadius, yRadius: CaptureStyle.selectionRadius))
            path.windingRule = .evenOdd
        }
        CaptureStyle.dim.setFill()
        path.fill()
    }

    private func drawFrame(_ rect: CGRect, isWindow: Bool) {
        let r = CaptureStyle.selectionRadius
        let outline = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
        // Soft glow, then the gradient stroke on top.
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
        ring.lineWidth = isWindow ? 3 : 2
        NSGraphicsContext.saveGraphicsState()
        let strokeArea = NSBezierPath(roundedRect: rect.insetBy(dx: -2, dy: -2), xRadius: r + 2, yRadius: r + 2)
        strokeArea.append(NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: r, yRadius: r))
        strokeArea.windingRule = .evenOdd
        strokeArea.addClip()
        CaptureStyle.accentGradient.draw(in: ring.bounds.insetBy(dx: -2, dy: -2), angle: -30)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSizeLabel(for rect: CGRect) {
        let px = CaptureGeometry.pixelRect(fromView: rect, scale: scale, imageSize: CGSize(width: image.width, height: image.height))
        let text = NSAttributedString(
            string: "\(Int(px.width)) × \(Int(px.height))",
            attributes: CaptureStyle.label(CaptureStyle.mono(12))
        )
        let size = text.size()
        let box = CGSize(width: size.width + 18, height: size.height + 8)
        var origin = CGPoint(x: rect.minX, y: rect.minY - box.height - 8)
        if origin.y < bounds.minY + 4 { origin.y = rect.minY + 8; origin.x = rect.minX + 8 }
        drawCapsule(CGRect(origin: origin, size: box))
        text.draw(at: CGPoint(x: origin.x + 9, y: origin.y + 4))
    }

    private func drawCrosshair(at p: CGPoint) {
        NSColor(white: 1, alpha: 0.35).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.setLineDash([4, 4], count: 2, phase: 0)
        path.move(to: CGPoint(x: bounds.minX, y: p.y.rounded() + 0.5))
        path.line(to: CGPoint(x: bounds.maxX, y: p.y.rounded() + 0.5))
        path.move(to: CGPoint(x: p.x.rounded() + 0.5, y: bounds.minY))
        path.line(to: CGPoint(x: p.x.rounded() + 0.5, y: bounds.maxY))
        path.stroke()
    }

    /// Round magnifier: 11×11 real pixels at 12×, a grid, the center pixel
    /// highlighted, and its position + color underneath.
    private func drawLoupe(at p: CGPoint) {
        let pixels = 11
        let zoom: CGFloat = 12
        let diameter = CGFloat(pixels) * zoom
        let infoHeight: CGFloat = 26
        let origin = CaptureGeometry.loupeOrigin(
            cursor: p, loupe: CGSize(width: diameter, height: diameter + infoHeight + 6), bounds: bounds
        )
        let circle = CGRect(origin: origin, size: CGSize(width: diameter, height: diameter))

        let cx = Int((p.x * scale).rounded(.down))
        let cy = Int((p.y * scale).rounded(.down))
        let half = pixels / 2
        let source = CGRect(x: cx - half, y: cy - half, width: pixels, height: pixels)

        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(ovalIn: circle)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = 16
        shadow.set()
        NSColor.black.setFill()
        clip.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        if let crop = image.cropping(to: source) {
            NSGraphicsContext.current?.imageInterpolation = .none
            // Pixels outside the screen edge: shift so the crop stays aligned.
            let dx = CGFloat(Int(source.minX) < 0 ? -Int(source.minX) : 0) * zoom
            let dy = CGFloat(Int(source.minY) < 0 ? -Int(source.minY) : 0) * zoom
            NSImage(cgImage: crop, size: .zero).draw(
                in: CGRect(x: circle.minX + dx, y: circle.minY + dy, width: CGFloat(crop.width) * zoom, height: CGFloat(crop.height) * zoom),
                from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none]
            )
        }
        NSColor(white: 1, alpha: 0.10).setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = 0.5
        for i in 1..<pixels {
            let o = CGFloat(i) * zoom
            grid.move(to: CGPoint(x: circle.minX + o, y: circle.minY)); grid.line(to: CGPoint(x: circle.minX + o, y: circle.maxY))
            grid.move(to: CGPoint(x: circle.minX, y: circle.minY + o)); grid.line(to: CGPoint(x: circle.maxX, y: circle.minY + o))
        }
        grid.stroke()
        let center = CGRect(x: circle.minX + CGFloat(half) * zoom, y: circle.minY + CGFloat(half) * zoom, width: zoom, height: zoom)
        NSColor.white.setStroke()
        let centerBox = NSBezierPath(rect: center.insetBy(dx: 0.5, dy: 0.5))
        centerBox.lineWidth = 1.5
        centerBox.stroke()
        NSGraphicsContext.restoreGraphicsState()

        let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 1, dy: 1))
        ring.lineWidth = 2
        NSGraphicsContext.saveGraphicsState()
        let band = NSBezierPath(ovalIn: circle.insetBy(dx: -1, dy: -1))
        band.append(NSBezierPath(ovalIn: circle.insetBy(dx: 2, dy: 2)))
        band.windingRule = .evenOdd
        band.addClip()
        CaptureStyle.accentGradient.draw(in: circle.insetBy(dx: -2, dy: -2), angle: -30)
        NSGraphicsContext.restoreGraphicsState()

        // Position + color chip.
        let hex = pixelHex(x: cx, y: cy)
        let text = NSAttributedString(string: "\(cx), \(cy)   \(hex)", attributes: CaptureStyle.label(CaptureStyle.mono(11)))
        let ts = text.size()
        let chip: CGFloat = 10
        let boxWidth = ts.width + chip + 26
        let box = CGRect(x: circle.midX - boxWidth / 2, y: circle.maxY + 6, width: boxWidth, height: infoHeight)
        drawCapsule(box)
        if let color = pixelColor(x: cx, y: cy) {
            color.setFill()
            NSBezierPath(roundedRect: CGRect(x: box.minX + 10, y: box.midY - chip / 2, width: chip, height: chip), xRadius: 3, yRadius: 3).fill()
        }
        text.draw(at: CGPoint(x: box.minX + 10 + chip + 6, y: box.midY - ts.height / 2))
    }

    private func drawHints() {
        var keys: [(String, String)] = [(String(localized: "drag"), String(localized: "area")), (String(localized: "click"), String(localized: "window")), ("↩", String(localized: "full screen"))]
        if canRepeat { keys.append(("R", String(localized: "repeat"))) }
        keys.append(("C", String(localized: "copy color")))
        keys.append(("S", scrolling ? String(localized: "scrolling: on") : String(localized: "scrolling")))
        keys.append(("esc", String(localized: "cancel")))

        // The windows' Leaves look: a light leaf panel, green keys, dark ink.
        let keyFont = CaptureStyle.font(13, .bold)
        let textFont = CaptureStyle.font(14, .medium)
        let parts = keys.map { (NSAttributedString(string: $0.0, attributes: CaptureStyle.label(keyFont, color: CaptureStyle.forest)),
                                NSAttributedString(string: $0.1, attributes: CaptureStyle.label(textFont, color: CaptureStyle.forest.withAlphaComponent(0.8)))) }
        let gap: CGFloat = 22
        let width = parts.reduce(0) { $0 + $1.0.size().width + 16 + 8 + $1.1.size().width } + gap * CGFloat(parts.count - 1) + 36
        let height: CGFloat = 48
        // Above the Dock (the screen's visible area), with room to breathe.
        let dock = window?.screen.map { $0.visibleFrame.minY - $0.frame.minY } ?? 0
        let box = CGRect(x: bounds.midX - width / 2, y: bounds.maxY - dock - height - 56, width: width, height: height)
        // Don't cover what the user is pointing at.
        if let cursor, box.insetBy(dx: -20, dy: -20).contains(cursor) { return }

        let shape = NSBezierPath(roundedRect: box, xRadius: 14, yRadius: 14)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.set()
        CaptureStyle.panel.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: CaptureStyle.leaf.withAlphaComponent(0.16), ending: CaptureStyle.leaf.withAlphaComponent(0))?
            .draw(in: shape, angle: -90) // the green wash from the top, like the windows
        NSColor.black.withAlphaComponent(0.10).setStroke()
        shape.lineWidth = 1
        shape.stroke()

        var x = box.minX + 18
        for (key, label) in parts {
            let ks = key.size()
            let cap = CGRect(x: x, y: box.midY - 13, width: ks.width + 16, height: 26)
            CaptureStyle.leaf.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: cap, xRadius: 7, yRadius: 7).fill()
            key.draw(at: CGPoint(x: cap.minX + 8, y: box.midY - ks.height / 2))
            x = cap.maxX + 8
            label.draw(at: CGPoint(x: x, y: box.midY - label.size().height / 2))
            x += label.size().width + gap
        }
    }

    private func drawCapsule(_ rect: CGRect, radius: CGFloat? = nil) {
        let r = radius ?? rect.height / 2
        let path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
        CaptureStyle.capsule.setFill()
        path.fill()
        CaptureStyle.capsuleStroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    // MARK: Pixels

    private func pixelColor(x: Int, y: Int) -> NSColor? {
        guard x >= 0, y >= 0, x < image.width, y < image.height,
              let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))
        else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return NSColor(srgbRed: CGFloat(rgba[0]) / 255, green: CGFloat(rgba[1]) / 255, blue: CGFloat(rgba[2]) / 255, alpha: 1)
    }

    private func pixelHex(x: Int, y: Int) -> String {
        guard let c = pixelColor(x: x, y: y) else { return "—" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}
