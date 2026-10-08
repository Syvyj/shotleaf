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

/// A key drawn as a small rounded cap: "↩", "esc", "⌘C".
struct Keycap: View {
    let key: String
    var body: some View {
        Text(key)
            .font(Leaf.font(10, .semibold))
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
                    Text(item.label).font(Leaf.font(11)).foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.secondary)
    }
}

/// Primary: green gradient. Secondary: quiet tinted fill.
struct LeafButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Leaf.font(12, .semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .foregroundStyle(prominent ? Leaf.forest : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(prominent ? AnyShapeStyle(Leaf.accent) : AnyShapeStyle(.primary.opacity(0.07)))
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(prominent ? 0 : 0.08)))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Capsule showing which model answers; amber when it's the Mock.
struct ProviderChip: View {
    let name: String
    let isMock: Bool
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(isMock ? Leaf.amber : Leaf.ink).frame(width: 6, height: 6)
            Text(isMock ? "Mock — no model" : name)
                .font(Leaf.font(10, .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
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
            .font(Leaf.font(13))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}
