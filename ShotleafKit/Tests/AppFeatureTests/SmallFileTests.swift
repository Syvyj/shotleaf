import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AppFeature

/// Noise pictures (JPEG can't squeeze noise) and a HEIC file.
enum TestImages {
    static func noise(width: Int, height: Int) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        var seed: UInt32 = 7
        for i in bytes.indices { seed = seed &* 1_664_525 &+ 1_013_904_223; bytes[i] = UInt8(seed >> 24) }
        return bytes.withUnsafeMutableBytes {
            CGContext(data: $0.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        }
    }

    static func writeHEIC(width: Int, height: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).heic")
        let image = try #require(noise(width: width, height: height))
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        try #require(CGImageDestinationFinalize(dest))
        return url
    }
}

@Suite("Small JPEG")
struct SmallFileTests {
    @Test func limitsMatchSpec() { #expect(SmallFile.limits == [200_000, 500_000, 1_000_000, 8_000_000, 25_000_000]) }

    @Test func tallShotFitsUnderLimit() async throws {
        let image = try #require(TestImages.noise(width: 2000, height: 30000))
        let data = try #require(await SmallFile.jpeg(image, under: 1_000_000))
        #expect(data.count <= 1_000_000)
    }

    @Test func heicFileCompresses() async throws {
        let url = try TestImages.writeHEIC(width: 3000, height: 2000)
        let data = try #require(await SmallFile.jpeg(contentsOf: url, under: 500_000))
        #expect(data.count <= 500_000 && data.starts(with: [0xFF, 0xD8, 0xFF]))
    }

    @MainActor @Test func copyPutsJPEGAndFileNoPNG() throws {
        SmallFile.copy(Data([0xFF, 0xD8, 0xFF, 0xD9]))
        let types = NSPasteboard.general.types ?? []
        #expect(types.contains(.init("public.jpeg")) && types.contains(.fileURL) && types.contains(ClipboardHistory.ownType))
        // `types` adds a TIFF the system converts on demand; what we wrote is on the item.
        let written = NSPasteboard.general.pasteboardItems?.first?.types ?? []
        #expect(!written.contains(.png) && !written.contains(.tiff))
    }
}
