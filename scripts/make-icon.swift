// Generates APILA's app icon set (all macOS sizes) into App/Assets.xcassets.
// Run: swift scripts/make-icon.swift [preview.png]
//
// The mark: selection-corner brackets with an AI spark inside — "select, and
// APILA acts". Same mark as the menu bar icon (AppFeature/BrandMark.swift).
import AppKit

// "Leaves" palette: deep forest → leaf → lime (from the user's reference photo).
let forest = NSColor(srgbRed: 0x12 / 255.0, green: 0x1A / 255.0, blue: 0x12 / 255.0, alpha: 1)
let moss = NSColor(srgbRed: 0x2E / 255.0, green: 0x4A / 255.0, blue: 0x24 / 255.0, alpha: 1)
let leaf = NSColor(srgbRed: 0x4F / 255.0, green: 0x7F / 255.0, blue: 0x2A / 255.0, alpha: 1)
let lime = NSColor(srgbRed: 0xC9 / 255.0, green: 0xE8 / 255.0, blue: 0x6A / 255.0, alpha: 1)

/// Four-point spark centered at `c` with tip radius `r`: four tips joined by
/// soft concave curves (fuller than a thin twinkle, so it reads at 16 px).
func spark(center c: CGPoint, radius r: CGFloat) -> NSBezierPath {
    let tips = (0..<4).map { i -> CGPoint in
        let a = CGFloat(i) * .pi / 2 + .pi / 2
        return CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
    }
    let p = NSBezierPath()
    p.move(to: tips[0])
    for i in 0..<4 {
        let next = tips[(i + 1) % 4]
        let mid = CGFloat(i) * .pi / 2 + .pi / 2 + .pi / 4
        let pull = CGPoint(x: c.x + cos(mid) * r * 0.16, y: c.y + sin(mid) * r * 0.16)
        p.curve(to: next, controlPoint1: pull, controlPoint2: pull)
    }
    p.close()
    return p
}

/// Two opposite selection corners (top-left, bottom-right) inside `rect`.
func corners(in rect: CGRect, arm: CGFloat, width: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.lineWidth = width
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

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // macOS icon grid: 824×824 rounded square centered on a 1024 canvas.
    let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    forest.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [forest, moss, leaf], atLocations: [0, 0.5, 1], colorSpace: .sRGB)!
        .draw(in: body, angle: 55)
    // A glow of fresh light behind the spark, like sun through leaves.
    NSGradient(starting: lime.withAlphaComponent(0.55), ending: lime.withAlphaComponent(0))!
        .draw(fromCenter: CGPoint(x: body.midX, y: body.midY), radius: 0,
              toCenter: CGPoint(x: body.midX, y: body.midY), radius: 330 * s, options: [])
    // Soft light from the top for depth.
    NSGradient(starting: NSColor.white.withAlphaComponent(0.10), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // The mark: lime corners, near-white spark.
    let markRect = body.insetBy(dx: 210 * s, dy: 210 * s)
    lime.setStroke()
    corners(in: markRect, arm: 120 * s, width: 46 * s).stroke()
    NSColor(srgbRed: 0.97, green: 1, blue: 0.90, alpha: 1).setFill()
    spark(center: CGPoint(x: body.midX, y: body.midY), radius: 168 * s).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: Output

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let set = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

var images: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try drawIcon(size: CGFloat(px)).representation(using: .png, properties: [:])!
            .write(to: set.appendingPathComponent(name))
        images.append(#"{"idiom":"mac","size":"\#(points)x\#(points)","scale":"\#(scale)x","filename":"\#(name)"}"#)
    }
}
try #"{"images":[\#(images.joined(separator: ","))],"info":{"author":"xcode","version":1}}"#
    .write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try #"{"info":{"author":"xcode","version":1}}"#
    .write(to: set.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

if CommandLine.arguments.count > 1 {
    try drawIcon(size: 1024).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
print("AppIcon written to \(set.path)")
