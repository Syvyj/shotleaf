import SwiftUI

/// APILA's own line icons for the annotation tools: 1.6-pt rounded strokes on
/// an 18-pt grid, so they share the soft feel of the brand mark.
struct ToolIcon: View {
    /// nil = the Select tool.
    let tool: AnnotationTool?
    var size: CGFloat = 18

    private var line: StrokeStyle { StrokeStyle(lineWidth: size / 11, lineCap: .round, lineJoin: .round) }

    var body: some View {
        Canvas { ctx, s in
            let u = s.width / 18 // grid unit
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * u, y: y * u, width: w * u, height: h * u) }
            let ink = GraphicsContext.Shading.foreground
            let soft = GraphicsContext.Shading.color(.primary.opacity(0.28))

            switch tool {
            case nil: // pointer
                var path = Path()
                path.move(to: p(4, 3)); path.addLine(to: p(4, 15)); path.addLine(to: p(7.4, 11.6))
                path.addLine(to: p(9.8, 16)); path.addLine(to: p(11.6, 15.1)); path.addLine(to: p(9.3, 10.8))
                path.addLine(to: p(14, 10.8)); path.closeSubpath()
                ctx.stroke(path, with: ink, style: line)
            case .arrow:
                var path = Path()
                path.move(to: p(3.5, 14.5)); path.addLine(to: p(14, 4))
                path.move(to: p(7.5, 3.8)); path.addLine(to: p(14.2, 3.8)); path.addLine(to: p(14.2, 10.5))
                ctx.stroke(path, with: ink, style: line)
            case .rectangle:
                ctx.stroke(Path(roundedRect: r(3, 4.5, 12, 9), cornerRadius: 2.2 * u), with: ink, style: line)
            case .text:
                var path = Path()
                path.move(to: p(4, 5.5)); path.addLine(to: p(4, 4)); path.addLine(to: p(14, 4)); path.addLine(to: p(14, 5.5))
                path.move(to: p(9, 4)); path.addLine(to: p(9, 14.5))
                path.move(to: p(7, 14.5)); path.addLine(to: p(11, 14.5))
                ctx.stroke(path, with: ink, style: line)
            case .highlight:
                ctx.fill(Path(roundedRect: r(2.5, 11.5, 13, 4), cornerRadius: 1.2 * u), with: soft)
                var nib = Path()
                nib.move(to: p(6, 12)); nib.addLine(to: p(12.5, 3.5)); nib.addLine(to: p(15, 5.5)); nib.addLine(to: p(8.5, 13.8)); nib.closeSubpath()
                ctx.stroke(nib, with: ink, style: line)
            case .blur:
                for (i, (x, y)) in [(3, 3), (8, 3), (13, 3), (3, 8), (8, 8), (13, 8), (3, 13), (8, 13), (13, 13)].enumerated() {
                    let shade: GraphicsContext.Shading = i.isMultiple(of: 2) ? ink : soft
                    ctx.fill(Path(roundedRect: r(CGFloat(x), CGFloat(y), 3.4, 3.4), cornerRadius: 0.8 * u), with: shade)
                }
            case .step:
                ctx.stroke(Path(ellipseIn: r(2.5, 2.5, 13, 13)), with: ink, style: line)
                var one = Path()
                one.move(to: p(7.6, 7)); one.addLine(to: p(9.4, 5.8)); one.addLine(to: p(9.4, 12.4))
                ctx.stroke(one, with: ink, style: line)
            case .erase:
                var body = Path()
                body.move(to: p(3.5, 11)); body.addLine(to: p(10, 4.5)); body.addLine(to: p(14.5, 9)); body.addLine(to: p(9.5, 14))
                body.addLine(to: p(6.5, 14)); body.closeSubpath()
                ctx.stroke(body, with: ink, style: line)
                var split = Path(); split.move(to: p(6.8, 7.7)); split.addLine(to: p(11.3, 12.2))
                ctx.stroke(split, with: ink, style: line)
                var floor = Path(); floor.move(to: p(9.5, 15.5)); floor.addLine(to: p(15, 15.5))
                ctx.stroke(floor, with: soft, style: line)
            case .cut:
                ctx.stroke(Path(roundedRect: r(2.5, 2.5, 9, 8), cornerRadius: 1.5 * u), with: ink,
                           style: StrokeStyle(lineWidth: size / 13, lineCap: .round, dash: [1.4 * u, 1.9 * u]))
                ctx.fill(Path(roundedRect: r(7.5, 7.5, 8, 7.5), cornerRadius: 1.8 * u), with: soft)
                ctx.stroke(Path(roundedRect: r(7.5, 7.5, 8, 7.5), cornerRadius: 1.8 * u), with: ink, style: line)
            case .ellipse:
                ctx.stroke(Path(ellipseIn: r(2.5, 4, 13, 10)), with: ink, style: line)
            case .crop:
                var path = Path()
                path.move(to: p(5, 1.5)); path.addLine(to: p(5, 13)); path.addLine(to: p(16.5, 13))
                path.move(to: p(1.5, 5)); path.addLine(to: p(13, 5)); path.addLine(to: p(13, 16.5))
                ctx.stroke(path, with: ink, style: line)
            case .ruler:
                var path = Path(roundedRect: r(1.5, 6, 15, 6), cornerRadius: 1.2 * u)
                for (i, x) in stride(from: 4.5, through: 13.5, by: 3).enumerated() {
                    path.move(to: p(x, 6)); path.addLine(to: p(x, i.isMultiple(of: 2) ? 9.5 : 8.2))
                }
                ctx.stroke(path, with: ink, style: line)
            case .focus:
                var dim = Path(roundedRect: r(1.5, 2.5, 15, 13), cornerRadius: 2.2 * u)
                dim.addPath(Path(roundedRect: r(5.5, 6, 7, 6), cornerRadius: 1.5 * u))
                ctx.fill(dim, with: soft, style: FillStyle(eoFill: true))
                ctx.stroke(Path(roundedRect: r(5.5, 6, 7, 6), cornerRadius: 1.5 * u), with: ink, style: line)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A line-thickness swatch: a short bar of the given width.
struct WidthIcon: View {
    let width: CGFloat
    var body: some View {
        Capsule()
            .frame(width: 14, height: min(width, 7))
            .frame(width: 18, height: 18)
    }
}
