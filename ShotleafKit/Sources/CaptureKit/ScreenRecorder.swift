import AVFoundation
import Core
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Where to record: a region of one display.
public struct RecordingArea: Sendable, Equatable {
    public let displayID: CGDirectDisplayID
    /// Points, top-left origin of that display.
    public let rect: CGRect
    /// Pixels per point of that display.
    public let scale: CGFloat

    public init(displayID: CGDirectDisplayID, rect: CGRect, scale: CGFloat) {
        self.displayID = displayID
        self.rect = rect
        self.scale = scale
    }
}

/// Records an area of the screen to an H.264 MP4 with ScreenCaptureKit's
/// `SCRecordingOutput`: native pixels, up to 30 fps, cursor and clicks shown, no audio.
/// `SCRecordingOutput` can't pause, so each stretch between pauses is its own file
/// (`Recording-1.mp4`, `Recording-2.mp4`, …), joined on `stop()`.
public actor ScreenRecorder {
    private var stream: SCStream?
    private var output: SCRecordingOutput? // nil while paused
    private var finish: RecordingFinish?
    private var ended: StreamEnded? // SCStream keeps its delegate weakly
    private var url: URL?
    private var segments: [URL] = []

    public init() {}

    /// Starts writing `area` to `url`. `windowIDs`: our own windows (the frame
    /// around the area, the controls) that must not be in the video. `endedBySystem`: macOS stopped
    /// the stream itself (display gone, "Stop sharing"); call `stop()` to get the file.
    public func start(_ area: RecordingArea, to url: URL, excluding windowIDs: [CGWindowID],
                      endedBySystem: @escaping @Sendable () -> Void = {}) async throws {
        guard stream == nil else { throw AppError.missingContext(String(localized: "Already recording")) }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw AppError.permissionDenied("Screen Recording")
        }
        guard let display = content.displays.first(where: { $0.displayID == area.displayID }) else {
            throw AppError.missingContext(String(localized: "The screen to record is gone"))
        }
        let excluded = content.windows.filter { windowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)

        let ended = StreamEnded(endedBySystem)
        let stream = SCStream(filter: filter, configuration: Self.recordingConfig(for: area), delegate: ended)
        (self.stream, self.ended, self.url, self.segments) = (stream, ended, url, [])
        do {
            try addSegment() // before startCapture, or nothing is written
            try await stream.startCapture()
        } catch {
            (self.stream, self.output, self.finish, self.ended, self.url, self.segments) = (nil, nil, nil, nil, nil, [])
            throw error
        }
    }

    /// Finishes the current segment; the stream keeps running, nothing is written.
    public func pause() async throws {
        guard let stream, let output, let finish else { throw AppError.missingContext(String(localized: "Not recording")) }
        try stream.removeRecordingOutput(output)
        (self.output, self.finish) = (nil, nil)
        _ = await finish.wait(timeout: .seconds(5))
    }

    /// Starts a new segment on the same stream.
    public func resume() async throws {
        guard stream != nil, output == nil else { throw AppError.missingContext(String(localized: "Not recording")) }
        try addSegment()
    }

    /// Stops and returns the finished file (the URL given to `start`).
    public func stop() async throws -> URL {
        guard let url else { throw AppError.missingContext(String(localized: "Not recording")) }
        let segments = await end()
        return try await Self.join(segments, into: url)
    }

    /// Stops and throws everything away: the segments and anything at the final URL.
    public func cancel() async {
        let url = self.url
        for file in await end() + [url].compactMap({ $0 }) { try? FileManager.default.removeItem(at: file) }
    }

    /// Stops capture, waits for the current segment; the segments written.
    private func end() async -> [URL] {
        let (stream, finish, segments) = (self.stream, self.finish, self.segments)
        (self.stream, self.output, self.finish, self.ended, self.url, self.segments) = (nil, nil, nil, nil, nil, [])
        try? await stream?.stopCapture()
        // The file is complete only once the output says so. Stopped right after
        // start, it may never say anything: wait a little, then take what's there.
        _ = await finish?.wait(timeout: .seconds(5)) // a failure here is SCK’s raw words: `join`'s message says it better
        return segments
    }

    private func addSegment() throws {
        guard let stream, let url else { return }
        let segment = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-\(segments.count + 1).\(url.pathExtension)")
        let settings = SCRecordingOutputConfiguration()
        settings.outputURL = segment
        settings.outputFileType = .mp4
        settings.videoCodecType = .h264
        let finish = RecordingFinish()
        let output = SCRecordingOutput(configuration: settings, delegate: finish)
        try stream.addRecordingOutput(output)
        (self.output, self.finish) = (output, finish)
        segments.append(segment)
    }

    /// Joins `segments` back to back into `url` without re-encoding and deletes them.
    /// Empty, missing or video-less ones are skipped; a single one is just moved.
    static func join(_ segments: [URL], into url: URL) async throws -> URL {
        let files = FileManager.default
        let written = segments.filter { ((try? files.attributesOfItem(atPath: $0.path)[.size] as? Int) ?? 0) > 0 }
        // The asset too: a track whose asset is gone can't be inserted.
        var tracks: [(url: URL, asset: AVURLAsset, track: AVAssetTrack)] = []
        for segment in written {
            let asset = AVURLAsset(url: segment)
            if let track = try? await asset.loadTracks(withMediaType: .video).first { tracks.append((segment, asset, track)) }
        }
        guard let first = tracks.first else {
            for segment in segments where !written.contains(segment) { try? files.removeItem(at: segment) } // empty ones only
            throw AppError.missingContext(String(localized: "Nothing was recorded — it was stopped too soon"))
        }
        // Deleted only once `url` is written: on a failure they are the only copy.
        func joined() -> URL {
            for segment in segments where segment != url { try? files.removeItem(at: segment) }
            return url
        }
        if tracks.count == 1 {
            if first.url != url {
                try? files.removeItem(at: url)
                try files.moveItem(at: first.url, to: url)
            }
            return joined()
        }
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AppError.missingContext(String(localized: "Couldn’t record the screen"))
        }
        track.preferredTransform = try await first.track.load(.preferredTransform)
        for (_, _, source) in tracks {
            try track.insertTimeRange(try await source.load(.timeRange), of: source, at: composition.duration)
        }
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw AppError.missingContext(String(localized: "Couldn’t record the screen"))
        }
        try? files.removeItem(at: url)
        try await export.export(to: url, as: .mp4)
        return joined()
    }

    /// What `start` asks ScreenCaptureKit for.
    static func recordingConfig(for area: RecordingArea) -> SCStreamConfiguration {
        // H.264 wants even sizes.
        func even(_ points: CGFloat) -> Int {
            let pixels = Int((points * area.scale).rounded(.up))
            return pixels + pixels % 2
        }
        let config = SCStreamConfiguration()
        config.sourceRect = area.rect
        config.width = even(area.rect.width)
        config.height = even(area.rect.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.showMouseClicks = true
        config.capturesAudio = false
        return config
    }
}

/// The stream's delegate: tells when the system ended the stream.
final class StreamEnded: NSObject, SCStreamDelegate, Sendable {
    private let handler: @Sendable () -> Void

    init(_ handler: @escaping @Sendable () -> Void) { self.handler = handler }

    func stream(_ stream: SCStream, didStopWithError error: any Error) { handler() }
}

/// The recording output's delegate: reports when the file is finished (or failed).
private final class RecordingFinish: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var result: Error?? // nil: still writing; .some(nil): finished; .some(error): failed
    private var waiter: CheckedContinuation<Error?, Never>?

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { done(nil) }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) { done(error) }

    private func done(_ error: Error?) {
        let waiter: CheckedContinuation<Error?, Never>? = lock.withLock {
            guard result == nil else { return nil }
            result = .some(error)
            defer { self.waiter = nil }
            return self.waiter
        }
        waiter?.resume(returning: error)
    }

    /// The failure, if any, once the file is finished; nil after `timeout` as well.
    func wait(timeout: Duration) async -> Error? {
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            self?.done(nil)
        }
        defer { timer.cancel() }
        return await withCheckedContinuation { continuation in
            let finished: Error?? = lock.withLock {
                if result == nil { waiter = continuation }
                return result
            }
            if let finished { continuation.resume(returning: finished) }
        }
    }
}
