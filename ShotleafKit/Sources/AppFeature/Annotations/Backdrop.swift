import AppKit
import SwiftUI
import Vision
import CoreImage

/// "Фон": the result laid on a gradient or a color, with room around it,
/// rounded corners and a soft shadow — for posts and docs.
struct Backdrop: Equatable {
    enum Fill: Hashable {
        case gradient(Int)
        case solid(Int)
    }

    var fill: Fill = .gradient(0)
    /// Room around the shot, in image points.
    var padding: CGFloat = 48
    var corner: CGFloat = 12

    static let paddingRange: ClosedRange<CGFloat> = 0...120
    static let cornerRange: ClosedRange<CGFloat> = 0...32

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// Top-left → bottom-right pairs.
    static let gradients: [(NSColor, NSColor)] = [
        (rgb(0x8FBF3A), rgb(0xC9E86A)), // leaves
        (rgb(0x3B82F6), rgb(0x7DD3FC)), // sky
        (rgb(0xF0606A), rgb(0xF8B55A)), // sunset
        (rgb(0x2F7D5B), rgb(0xA3D97A)), // forest
        (rgb(0xA855F7), rgb(0xF0A0C0)), // lilac
        (rgb(0x2B3240), rgb(0x6B7385)), // slate
    ]
    static let solids: [NSColor] = [
        .white, rgb(0xEDEFF2), rgb(0xFBF3E4), rgb(0x121A12), rgb(0x4F7F2A), rgb(0x3B82F6), rgb(0xF0606A), rgb(0xF8B55A),
    ]

    var colors: (NSColor, NSColor) {
        switch fill {
        case .gradient(let i): Self.gradients[i % Self.gradients.count]
        case .solid(let i): (Self.solids[i % Self.solids.count], Self.solids[i % Self.solids.count])
        }
    }

    /// The same fill for the live preview.
    var style: LinearGradient {
        LinearGradient(colors: [Color(nsColor: colors.0), Color(nsColor: colors.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// `image` laid on the backdrop. `scale` = pixels per image point.
    func framed(_ image: CGImage, scale: CGFloat) -> CGImage? {
        let pad = (padding * scale).rounded()
        let size = CGSize(width: CGFloat(image.width) + 2 * pad, height: CGFloat(image.height) + 2 * pad)
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: [colors.0.cgColor, colors.1.cgColor] as CFArray, locations: [0, 1])
        else { return nil }
        // y up here: top-left is (0, height).
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
        let shot = CGRect(x: pad, y: pad, width: CGFloat(image.width), height: CGFloat(image.height))
        let rounded = CGPath(roundedRect: shot, cornerWidth: corner * scale, cornerHeight: corner * scale, transform: nil)
        if pad > 0 {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -6 * scale), blur: 24 * scale, color: NSColor.black.withAlphaComponent(0.28).cgColor)
            ctx.addPath(rounded)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.addPath(rounded)
        ctx.clip()
        // Under the shot too, so a cut-out shows the backdrop, not the shadow fill.
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
        ctx.draw(image, in: shot)
        return ctx.makeImage()
    }
}

/// "Remove background": keeps the main subject (Vision's foreground mask),
/// the rest becomes transparent. Nil when Vision finds no subject.
enum BackgroundRemover {
    static func cutOut(_ image: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              let buffer = try? observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler,
                                                                croppedToInstancesExtent: false)
        else { return nil }
        let ci = CIImage(cvPixelBuffer: buffer)
        return CIContext().createCGImage(ci, from: ci.extent)
    }
}
