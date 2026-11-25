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
        let asset = AVURLAsset(url: source)
        let range = try await clamped(range, to: asset)
        let out = TempFolder.recordings.new().appendingPathComponent("Recording.mp4")
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
        else { throw VideoEditError.failed }
        session.timeRange = range
        try await session.export(to: out, as: .mp4)
        return out
    }

    /// `range` cut to the asset's length; throws unless something of positive, finite length is left.
    private static func clamped(_ range: CMTimeRange, to asset: AVURLAsset) async throws -> CMTimeRange {
        let whole = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        let range = range.intersection(whole)
        guard range.isValid, range.duration.seconds.isFinite, range.duration.seconds > 0 else { throw VideoEditError.failed }
        return range
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
        let range = try await clamped(range, to: asset)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoEditError.failed }
        let (natural, nominal) = try await track.load(.naturalSize, .nominalFrameRate)
        let fps = max(1, nominal)  // a screen recording can report 0
        var rate = bitrate(under: bytes, seconds: range.duration.seconds)
        // The size is chosen once: a retry only lowers the bitrate (a smaller frame can come out bigger).
        let factor = scale(bitrate: rate, width: Int(natural.width), height: Int(natural.height), fps: Int(fps.rounded()))
        let size = CGSize(width: Int(natural.width * factor) / 2 * 2, height: Int(natural.height * factor) / 2 * 2)
        for attempt in 1...2 {
            let out = try await encode(asset, track: track, range: range, size: size, fps: fps, bitrate: rate)
            let written = try out.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            if written <= bytes { return out }
            try? FileManager.default.removeItem(at: out)
            if attempt == 1 { rate = Int(Double(rate) * Double(bytes) / Double(written) * 0.95) }
        }
        throw VideoEditError.tooLong
    }

    /// Streams decoded frames of `range` into a new H.264 file of `size` at `bitrate`.
    private static func encode(_ asset: AVURLAsset, track: AVAssetTrack, range: CMTimeRange,
                               size: CGSize, fps: Float, bitrate rate: Int) async throws -> URL {

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
            AVVideoWidthKey: max(2, size.width), AVVideoHeightKey: max(2, size.height),
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

    /// ImageIO holds every GIF frame until it finalizes (~4 MB per 960×600 frame), so a long GIF gets smaller frames.
    static let gifPixelBudget = 60_000_000

    /// The longest side (≤ 960) that keeps 12 fps × `seconds` frames of a `width`×`height` video within `gifPixelBudget`.
    static func gifLongSide(seconds: Double, width: Int, height: Int) -> Int {
        let frames = Double(max(1, Int((seconds * 12).rounded())))
        let ratio = Double(min(width, height)) / Double(max(width, height, 1))
        var side = min(960, Int(sqrt(Double(gifPixelBudget) / (frames * max(ratio, 0.01)))))
        while side > 2, frames * Double(side) * (Double(side) * ratio).rounded(.up) > Double(gifPixelBudget) { side -= 1 }
        return max(2, side)
    }

    /// 12 frames a second of `range`, long side at most 960 (less for long ranges), looping forever.
    static func gif(_ source: URL, range: CMTimeRange) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let range = try await clamped(range, to: asset)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoEditError.failed }
        let natural = try await track.load(.naturalSize)
        let side = gifLongSide(seconds: range.duration.seconds, width: Int(natural.width), height: Int(natural.height))

        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: side, height: side)
        let count = max(1, Int((range.duration.seconds * 12).rounded()))
        let times = (0..<count).map { range.start + CMTime(value: CMTimeValue($0), timescale: 12) }

        let out = TempFolder.recordings.new().appendingPathComponent("Recording.gif")
        guard let gif = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, count, nil)
        else { throw VideoEditError.failed }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        // GIF delays are whole hundredths: 8, 8, 9 averages 1/12 s.
        func frame(_ i: Int) -> CFDictionary { [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: i % 3 == 2 ? 0.09 : 0.08]] as CFDictionary }
        do {
            var i = 0
            for await result in generator.images(for: times) {
                CGImageDestinationAddImage(gif, try result.image, frame(i))
                i += 1
            }
            guard CGImageDestinationFinalize(gif) else { throw VideoEditError.failed }
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
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
