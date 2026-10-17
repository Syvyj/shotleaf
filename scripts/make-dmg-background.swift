// The picture behind the disk image's window: Shotleaf on the left, Applications on the
// right, an arrow between them. Run: swift scripts/make-dmg-background.swift <dir>
// → <dir>/background.png and background@2x.png (make-release.sh joins them into one TIFF).
// The places of the icons are in scripts/dmg-settings.py: keep them in step.
import AppKit

let size = CGSize(width: 640, height: 400)
let app = CGPoint(x: 170, y: 210), apps = CGPoint(x: 470, y: 210) // icon centres, y down

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let paper = rgb(0xF3F4EE), ink = rgb(0x0F150C), leaf = rgb(0x4F7F2A), fresh = rgb(0x8FBF3A), lime = rgb(0xC6E86B)

func draw(scale: CGFloat, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1) // y down, like Finder's icon places
    let flipped = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.current = flipped

    // The site's paper with a faint fresh glow where the icons stand. Light, because Finder
    // writes the icons' names in black on a window with a picture, in light and dark mode.
    paper.setFill(); CGRect(origin: .zero, size: size).fill()
    NSGradient(colors: [lime.withAlphaComponent(0.35), paper.withAlphaComponent(0)])!
        .draw(fromCenter: CGPoint(x: 320, y: 210), radius: 0, toCenter: CGPoint(x: 320, y: 210), radius: 330, options: [])

    // The line on top, in both languages.
    func text(_ s: String, _ font: NSFont, _ color: NSColor, y: CGFloat) {
        let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        a.draw(at: CGPoint(x: (size.width - a.size().width) / 2, y: y))
    }
    text("Drag Shotleaf into Applications", .systemFont(ofSize: 20, weight: .semibold), ink, y: 44)
    text("Перетягніть Shotleaf у Програми", .systemFont(ofSize: 14, weight: .regular), leaf, y: 74)

    // Selection corners around each icon, as in the capture picker.
    for c in [app, apps] {
        let r = CGRect(x: c.x - 90, y: c.y - 84, width: 180, height: 182), arm: CGFloat = 18 // the icon and its name
        let p = NSBezierPath(); p.lineWidth = 3; p.lineCapStyle = .round; p.lineJoinStyle = .round
        for (corner, dx, dy) in [(CGPoint(x: r.minX, y: r.minY), 1.0, 1.0), (CGPoint(x: r.maxX, y: r.minY), -1.0, 1.0),
                                 (CGPoint(x: r.minX, y: r.maxY), 1.0, -1.0), (CGPoint(x: r.maxX, y: r.maxY), -1.0, -1.0)] {
            p.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm)); p.line(to: corner); p.line(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        }
        leaf.withAlphaComponent(0.6).setStroke(); p.stroke()
    }

    // The arrow from the app to Applications.
    let arrow = NSBezierPath(); arrow.lineWidth = 4; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    arrow.move(to: CGPoint(x: 272, y: 210)); arrow.line(to: CGPoint(x: 366, y: 210))
    arrow.move(to: CGPoint(x: 352, y: 198)); arrow.line(to: CGPoint(x: 368, y: 210)); arrow.line(to: CGPoint(x: 352, y: 222))
    fresh.setStroke(); arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let dir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
draw(scale: 1, to: dir.appendingPathComponent("background.png"))
draw(scale: 2, to: dir.appendingPathComponent("background@2x.png"))
