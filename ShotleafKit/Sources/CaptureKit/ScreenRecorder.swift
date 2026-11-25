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
public actor ScreenRecorder {
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var finish: RecordingFinish?
    private var ended: StreamEnded? // SCStream keeps its delegate weakly
    private var url: URL?

    public init() {}

    /// Starts writing `area` to `url`. `windowIDs`: our own windows (the frame
    /// around the area) that must not be in the video. `endedBySystem`: macOS stopped
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

        let settings = SCRecordingOutputConfiguration()
        settings.outputURL = url
        settings.outputFileType = .mp4
        settings.videoCodecType = .h264
        let finish = RecordingFinish()
        let output = SCRecordingOutput(configuration: settings, delegate: finish)

        let ended = StreamEnded(endedBySystem)
        let stream = SCStream(filter: filter, configuration: Self.recordingConfig(for: area), delegate: ended)
        try stream.addRecordingOutput(output) // before startCapture, or nothing is written
        try await stream.startCapture()
        (self.stream, self.output, self.finish, self.ended, self.url) = (stream, output, finish, ended, url)
    }

    /// Stops and returns the finished file (the URL given to `start`).
    public func stop() async throws -> URL {
        guard let stream, let finish, let url else { throw AppError.missingContext(String(localized: "Not recording")) }
        (self.stream, self.output, self.finish, self.ended, self.url) = (nil, nil, nil, nil, nil)
        try? await stream.stopCapture()
        // The file is complete only once the output says so. Stopped right after
        // start, it may never say anything: wait a little, then take what's there.
        _ = await finish.wait(timeout: .seconds(5)) // a failure here is SCK’s raw words: the message below says it better
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard size > 0 else {
            throw AppError.missingContext(String(localized: "Nothing was recorded — it was stopped too soon"))
        }
        return url
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
