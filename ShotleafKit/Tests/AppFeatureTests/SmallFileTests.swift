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

    static func writeHEIC(width: Int, height: Int) throws -> URL { try write(.heic, width: width, height: height) }

    static func write(_ type: UTType, width: Int, height: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(for: type)
        let image = try #require(noise(width: width, height: height))
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        try #require(CGImageDestinationFinalize(dest))
        return url
    }
}

@Suite("Small JPEG")
struct SmallFileTests {
    @Test func limitsMatchSpec() { #expect(SmallFile.limits == [200_000, 500_000, 1_000_000, 8_000_000, 25_000_000]) }

    @Test func tallShotFitsUnderLimit() async throws {
        let url = try TestImages.write(.tiff, width: 2000, height: 30000) // TIFF: quick to write, unlike a PNG of noise
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try #require(await SmallFile.jpeg(contentsOf: url, under: 1_000_000))
        #expect(data.count <= 1_000_000)
    }

    @Test func heicFileCompresses() async throws {
        let url = try TestImages.writeHEIC(width: 3000, height: 2000)
        let data = try #require(await SmallFile.jpeg(contentsOf: url, under: 500_000))
        #expect(data.count <= 500_000 && data.starts(with: [0xFF, 0xD8, 0xFF]))
    }

    @Test func compressFileWritesJPEGUnderLimit() async throws {
        let png = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: png) }
        let image = try #require(TestImages.noise(width: 3000, height: 2000))
        let dest = try #require(CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        try #require(CGImageDestinationFinalize(dest))
        let url = try await SmallFile.compressFile(png, under: 500_000)
        let data = try Data(contentsOf: url)
        #expect(url.lastPathComponent == png.deletingPathExtension().lastPathComponent + ".jpg")
        #expect(data.count <= 500_000 && data.starts(with: [0xFF, 0xD8, 0xFF]))
    }

    @Test func compressImageFromBytesStaysInItsFolder() async throws {
        let image = try #require(TestImages.noise(width: 1500, height: 1000))
        let data = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        try #require(CGImageDestinationFinalize(dest))
        let url = try await SmallFile.compressImage(data: data as Data, filename: "../../evil.png", under: 200_000)
        #expect(url.lastPathComponent == "evil.jpg" && url.path.contains("Shotleaf Share"))
        #expect(try Data(contentsOf: url).count <= 200_000)
        let unnamed = try await SmallFile.compressImage(data: data as Data, filename: "", under: 200_000)
        #expect(unnamed.lastPathComponent == "Image.jpg")
        await #expect(throws: SmallFile.DoesNotFit.self) {
            try await SmallFile.compressImage(data: Data("not a picture".utf8), filename: "x.png", under: 200_000)
        }
    }
}
