import AVFoundation
import VideoToolbox
import ImageIO
import UniformTypeIdentifiers

enum VideoEditError: Error { case tooLong, failed }

/// Trim a recording, fit it under a size, make a GIF. Each writes a new file in a fresh
/// `TempFolder.recordings` folder; the source is never touched.
enum VideoEdit {
    /// Passthrough copy of `range` (no re-encoding).
    static func trim(_ source: URL, to range: CMTimeRange) async throws -> URL {
        let out = TempFolder.recordings.new().appendingPathComponent("Recording.mp4")
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetPassthrough)
        else { throw VideoEditError.failed }
        session.timeRange = range
        try await session.export(to: out, as: .mp4)
        return out
    }

    /// Bits per second that fit `bytes` in `seconds`, leaving 10 % for the container.
    static func bitrate(under bytes: Int, seconds: Double) -> Int { Int(Double(bytes) * 8 * 0.9 / seconds) }

    /// How much to shrink the frame so `bitrate` still gives a watchable picture (never below a quarter).
    static func scale(bitrate: Int, width: Int, height: Int, fps: Int) -> CGFloat {
        max(0.25, min(1, sqrt(Double(bitrate) / (Double(width * height * fps) * 0.05))))
    }

    /// Re-encodes `range` as H.264 at the bitrate that fits `bytes`; throws `tooLong` if it still doesn't.
    /// The encoder can overshoot its target, so a near miss is tried once more at a proportionally lower rate.
    static func fit(_ source: URL, range: CMTimeRange, under bytes: Int) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoEditError.failed }
        var rate = bitrate(under: bytes, seconds: range.duration.seconds)
        for attempt in 1...2 {
            let out = try await encode(asset, track: track, range: range, bitrate: rate)
            let size = try out.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            if size <= bytes { return out }
            try? FileManager.default.removeItem(at: out)
            if attempt == 1 { rate = Int(Double(rate) * Double(bytes) / Double(size) * 0.95) }
        }
        throw VideoEditError.tooLong
    }

    /// Streams decoded frames of `range` into a new H.264 file, scaled for `bitrate`.
    private static func encode(_ asset: AVURLAsset, track: AVAssetTrack, range: CMTimeRange, bitrate rate: Int) async throws -> URL {
        let (natural, fps) = try await track.load(.naturalSize, .nominalFrameRate)
        let factor = scale(bitrate: rate, width: Int(natural.width), height: Int(natural.height), fps: Int(fps.rounded()))
        func even(_ side: CGFloat) -> Int { max(2, Int(side * factor) / 2 * 2) }

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)

        let out = TempFolder.recordings.new().appendingPathComponent("Recording.mp4")
        let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: even(natural.width), AVVideoHeightKey: even(natural.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: rate, AVVideoExpectedSourceFrameRateKey: fps,
                // A hard cap per second too: the average alone drifts well over on busy frames.
                kVTCompressionPropertyKey_DataRateLimits as String: [rate / 8, 1],
            ],
        ])
        input.expectsMediaDataInRealTime = false
        writer.add(input)

        guard reader.startReading(), writer.startWriting() else { throw VideoEditError.failed }
        writer.startSession(atSourceTime: range.start)
        let pump = Pump(output: output, input: input)
        await withCheckedContinuation { done in pump.run { done.resume() } }
        if reader.status == .failed { writer.cancelWriting() } else { await writer.finishWriting() }

        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: out)
            throw reader.error ?? writer.error ?? VideoEditError.failed
        }
        return out
    }

    /// 12 frames a second of `range`, long side at most 960, looping forever.
    static func gif(_ source: URL, range: CMTimeRange) async throws -> URL {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        let count = max(1, Int((range.duration.seconds * 12).rounded()))
        let times = (0..<count).map { range.start + CMTime(value: CMTimeValue($0), timescale: 12) }

        let out = TempFolder.recordings.new().appendingPathComponent("Recording.gif")
        guard let gif = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, count, nil)
        else { throw VideoEditError.failed }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 12]] as CFDictionary
        for await result in generator.images(for: times) {
            CGImageDestinationAddImage(gif, try result.image, frame)
        }
        guard CGImageDestinationFinalize(gif) else {
            try? FileManager.default.removeItem(at: out)
            throw VideoEditError.failed
        }
        return out
    }
}

/// Moves decoded frames from reader to writer whenever the writer is ready. Touched only on its own queue.
private final class Pump: @unchecked Sendable {
    let output: AVAssetReaderTrackOutput, input: AVAssetWriterInput
    init(output: AVAssetReaderTrackOutput, input: AVAssetWriterInput) { (self.output, self.input) = (output, input) }

    func run(_ finished: @escaping @Sendable () -> Void) {
        input.requestMediaDataWhenReady(on: DispatchQueue(label: "Shotleaf.VideoEdit")) { [self] in
            while input.isReadyForMoreMediaData {
                guard let sample = output.copyNextSampleBuffer(), input.append(sample) else {
                    input.markAsFinished()
                    finished()
                    return
                }
            }
        }
    }
}
