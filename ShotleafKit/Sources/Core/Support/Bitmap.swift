import CoreGraphics

public extension CGContext {
    /// A new 8-bit sRGB bitmap to draw into (nil only if the size is zero or memory ran out).
    static func sRGB(width: Int, height: Int, alpha: CGImageAlphaInfo = .premultipliedLast) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: alpha.rawValue)
    }
}
