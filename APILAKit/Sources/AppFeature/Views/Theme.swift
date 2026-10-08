import SwiftUI
import AppKit

/// APILA's "Leaves" design system for SwiftUI: palette, keycaps, the spark mark,
/// buttons. Same palette as the app icon and the capture overlay.
enum Leaf {
    static let forest = Color(red: 0x12 / 255, green: 0x1A / 255, blue: 0x12 / 255)
    static let moss = Color(red: 0x2E / 255, green: 0x4A / 255, blue: 0x24 / 255)
    static let leaf = Color(red: 0x4F / 255, green: 0x7F / 255, blue: 0x2A / 255)
    static let fresh = Color(red: 0x8F / 255, green: 0xBF / 255, blue: 0x3A / 255)
    static let lime = Color(red: 0xC9 / 255, green: 0xE8 / 255, blue: 0x6A / 255)
    static let amber = Color(red: 0xE8 / 255, green: 0xA9 / 255, blue: 0x3C / 255)

    /// Readable accent for text and small marks: fresh green on dark, deeper leaf
    /// on light (lime would vanish on a light background).
    static let ink = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x8F / 255, green: 0xBF / 255, blue: 0x3A / 255, alpha: 1)
            : NSColor(srgbRed: 0x4F / 255, green: 0x7F / 255, blue: 0x2A / 255, alpha: 1)
    })

    /// Panel wash over the material: makes the light theme airy, leaves dark as is.
    static let surface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0, alpha: 0)
            : NSColor(white: 1, alpha: 0.62)
    })
    /// Cards inside the panel (context, result).
    static let card = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.05)
            : NSColor(white: 1, alpha: 0.85)
    })

    static let accent = LinearGradient(colors: [fresh, lime], startPoint: .leading, endPoint: .trailing)
    /// For small marks (spark, focus ring): stays visible on light backgrounds.
    static let markGradient = LinearGradient(colors: [ink, fresh], startPoint: .bottomLeading, endPoint: .topTrailing)
    static let selection = LinearGradient(
        colors: [fresh.opacity(0.30), lime.opacity(0.10)], startPoint: .leading, endPoint: .trailing
    )

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// The APILA spark (same geometry as the icon and menu bar mark).
struct SparkMark: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return Path(BrandMark.spark(center: center, radius: r).cgPath)
    }
}

/// APILA's mark for window headers — the icon's corners and spark without the
/// tile, drawn in colors that contrast with the window (light or dark).
struct BrandLogo: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            CornersShape().stroke(Leaf.ink, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round, lineJoin: .round))
            SparkMark().fill(Leaf.markGradient).padding(size * 0.16)
        }
        .frame(width: size, height: size)
    }
}

/// The two selection corners of the mark (SwiftUI's y axis points down, so the
/// AppKit path is flipped to keep top-left / bottom-right).
struct CornersShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08)
        let path = Path(BrandMark.corners(in: inset, arm: rect.width * 0.32).cgPath)
        return path.applying(CGAffineTransform(translationX: 0, y: rect.height).scaledBy(x: 1, y: -1))
    }
}

/// A key drawn as a small rounded cap: "↩", "esc", "⌘C".
struct Keycap: View {
    let key: String
    var body: some View {
        Text(key)
            .font(Leaf.font(11, .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.10)))
    }
}

/// Bottom hint line: keycap + what it does.
struct HintBar: View {
    let items: [(key: String, label: String)]
    var body: some View {
        HStack(spacing: 12) {
            ForEach(items, id: \.key) { item in
                HStack(spacing: 4) {
                    Keycap(key: item.key)
                    Text(item.label).font(Leaf.font(12))
                }
            }
        }
    }
}

/// Primary: green gradient. Secondary: quiet tinted fill. Both brighten on hover.
struct LeafButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        HoverableButton(configuration: configuration, prominent: prominent)
    }
}

private struct HoverableButton: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @State private var hovered = false

    var body: some View {
        configuration.label
            .font(Leaf.font(13, .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(prominent ? Leaf.forest : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(prominent ? AnyShapeStyle(Leaf.accent) : AnyShapeStyle(.primary.opacity(hovered ? 0.13 : 0.07)))
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(prominent ? 0 : 0.08)))
            .brightness(prominent && hovered ? 0.06 : 0)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onHover { hovered = $0 }
    }
}

/// Lets the user drag the borderless panel by this area (header, gaps).
struct WindowDragArea: NSViewRepresentable {
    /// Moves the window by hand: `performDrag(with:)` is ignored for our
    /// non-activating panel (APILA isn't the active app while it's shown).
    final class DragView: NSView {
        private var start: (mouse: NSPoint, origin: NSPoint)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            start = (NSEvent.mouseLocation, window.frame.origin)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start, let window else { return }
            let now = NSEvent.mouseLocation
            window.setFrameOrigin(NSPoint(x: start.origin.x + now.x - start.mouse.x,
                                          y: start.origin.y + now.y - start.mouse.y))
        }

        override func mouseUp(with event: NSEvent) { start = nil }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Capsule showing which model answers; amber when it's the Mock.
struct ProviderChip: View {
    let name: String
    let isMock: Bool
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(isMock ? Leaf.amber : Leaf.ink).frame(width: 6, height: 6)
            Text(isMock ? "Mock — no model" : name)
                .font(Leaf.font(11, .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.primary.opacity(0.06), in: Capsule())
    }
}

/// Text that takes only the height it needs, scrolling beyond `maxHeight`.
struct FittingScrollText: View {
    let text: String
    var color: Color = .primary
    var maxHeight: CGFloat = 260

    var body: some View {
        // Ideal height = the text's height, capped at maxHeight; scrolls beyond.
        ScrollView { label }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: maxHeight)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var label: some View {
        Text(text.isEmpty ? " " : text)
            .font(Leaf.font(15))
            .lineSpacing(2)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

/// Bottom-right grip that resizes the window by hand (like WindowDragArea —
/// system resizing is unreliable for our non-activating panels). Keeps the
/// top-left corner in place and respects the window's `contentMinSize`.
struct WindowResizeGrip: NSViewRepresentable {
    final class GripView: NSView {
        private var start: (mouse: NSPoint, frame: NSRect)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            start = (NSEvent.mouseLocation, window.frame)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start, let window else { return }
            let now = NSEvent.mouseLocation
            let min = window.contentMinSize
            let width = max(min.width, start.frame.width + now.x - start.mouse.x)
            let height = max(min.height, start.frame.height - (now.y - start.mouse.y))
            window.setFrame(NSRect(x: start.frame.minX, y: start.frame.maxY - height, width: width, height: height), display: true)
        }

        override func mouseUp(with event: NSEvent) { start = nil }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.secondaryLabelColor.withAlphaComponent(0.6).setStroke()
            let p = NSBezierPath()
            p.lineWidth = 1.4
            p.lineCapStyle = .round
            for k in [4.0, 8.0, 12.0] as [CGFloat] {
                p.move(to: NSPoint(x: bounds.maxX - k, y: bounds.minY + 2))
                p.line(to: NSPoint(x: bounds.maxX - 2, y: bounds.minY + k))
            }
            p.stroke()
        }
    }
    func makeNSView(context: Context) -> NSView { GripView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The look of every APILA floating window: glass, a light wash (light theme),
/// a breath of leaf green from the top, a hairline border; empty spots drag it.
struct LeafPanelChrome: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    WindowDragArea() // empty spots of the window drag it
                    shape.fill(.ultraThinMaterial).allowsHitTesting(false)
                    shape.fill(Leaf.surface).allowsHitTesting(false)
                    shape.fill(LinearGradient(colors: [Leaf.fresh.opacity(0.10), .clear], startPoint: .top, endPoint: .center))
                        .allowsHitTesting(false)
                }
            }
            .overlay(shape.strokeBorder(.primary.opacity(0.10)))
            .clipShape(shape)
    }
}

extension View {
    func leafPanelChrome() -> some View { modifier(LeafPanelChrome()) }
}
