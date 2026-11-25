import AVFoundation
import ImageIO
import Testing
@testable import AppFeature

/// H.264 test movies whose frames change every frame (noise sliding across the picture),
/// so the encoder can't squeeze them to nothing.
enum TestVideo {
    static func make(seconds: Double, width: Int, height: Int, fps: Int) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        // Blocks of noise (32 px), twice as wide as the frame; each frame shows a different window of it.
        let noiseWidth = width * 2, rowBytes = noiseWidth * 4
        var blocks = [UInt8](repeating: 0, count: (noiseWidth / 32 + 1) * (height / 32 + 1) * 4)
        var seed: UInt32 = 7
        for i in blocks.indices { seed = seed &* 1_664_525 &+ 1_013_904_223; blocks[i] = UInt8(seed >> 24) }
        var noise = [UInt8](repeating: 0, count: rowBytes * height)
        for i in noise.indices {
            let x = i % rowBytes / 4, y = i / rowBytes
            noise[i] = blocks[((y / 32) * (noiseWidth / 32 + 1) + x / 32) * 4 + i % 4]
        }

        for frame in 0..<Int(seconds * Double(fps)) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            let pool = try #require(adaptor.pixelBufferPool)
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let base = CVPixelBufferGetBaseAddress(pixels)!, stride = CVPixelBufferGetBytesPerRow(pixels)
            let shift = (frame * 13) % width * 4
            noise.withUnsafeBytes { src in
                for y in 0..<height {
                    memcpy(base + y * stride, src.baseAddress! + y * rowBytes + shift, width * 4)
                }
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            #expect(adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return url
    }
}

@Suite("Video edit")
struct VideoEditTests {
    private func seconds(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }
    private func size(_ url: URL) throws -> Int { try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 }

    @Test func bitrateFor8MBIn30s() { #expect(VideoEdit.bitrate(under: 8_000_000, seconds: 30) == 1_920_000) }

    @Test func scaleNeverBelowQuarter() {
        #expect(VideoEdit.scale(bitrate: 10_000, width: 3000, height: 2000, fps: 30) == 0.25)
        #expect(VideoEdit.scale(bitrate: 50_000_000, width: 800, height: 600, fps: 30) == 1)
    }

    @Test func trimKeepsRange() async throws {
        let source = try await TestVideo.make(seconds: 6, width: 640, height: 400, fps: 30)
        let before = try Data(contentsOf: source)
        let out = try await VideoEdit.trim(source, to: CMTimeRange(start: seconds(1), end: seconds(3)))
        #expect(out != source)
        let duration = try await AVURLAsset(url: out).load(.duration).seconds
        #expect(abs(duration - 2) <= 0.1)
        #expect(try Data(contentsOf: source) == before)
    }

    @Test func fitStaysUnderLimit() async throws {
        let source = try await TestVideo.make(seconds: 10, width: 1600, height: 1000, fps: 30)
        #expect(try size(source) > 2_000_000)
        let range = CMTimeRange(start: .zero, duration: seconds(10))
        let out = try await VideoEdit.fit(source, range: range, under: 500_000)
        #expect(try size(out) <= 500_000)
        let tracks = try await AVURLAsset(url: out).loadTracks(withMediaType: .video)
        #expect(tracks.count == 1)
        let natural = try #require(try await tracks.first?.load(.naturalSize))
        #expect(Int(natural.width) % 2 == 0 && Int(natural.height) % 2 == 0 && natural.width < 1600)
    }

    // ponytail: brief says 3000×2000 at 30 fps; 640×400 at 10 fps keeps it impossible (20 KB for 60 s)
    // without generating minutes of 6-megapixel frames in debug.
    @Test func fitThatCannotFitThrows() async throws {
        let source = try await TestVideo.make(seconds: 60, width: 640, height: 400, fps: 10)
        let range = CMTimeRange(start: .zero, duration: seconds(60))
        await #expect(throws: VideoEditError.tooLong) {
            try await VideoEdit.fit(source, range: range, under: 20_000)
        }
    }

    @Test func gifIsSmallAndLooping() async throws {
        let source = try await TestVideo.make(seconds: 2, width: 1920, height: 1080, fps: 30)
        let out = try await VideoEdit.gif(source, range: CMTimeRange(start: .zero, duration: seconds(2)))
        let gif = try #require(CGImageSourceCreateWithURL(out as CFURL, nil))
        #expect(abs(CGImageSourceGetCount(gif) - 24) <= 2)
        let frame = try #require(CGImageSourceCreateImageAtIndex(gif, 0, nil))
        #expect(max(frame.width, frame.height) == 960)
        let props = CGImageSourceCopyProperties(gif, nil) as? [CFString: Any]
        let gifProps = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        #expect(gifProps?[kCGImagePropertyGIFLoopCount] as? Int == 0)
    }
}
