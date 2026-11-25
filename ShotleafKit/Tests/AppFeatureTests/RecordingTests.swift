import AVFoundation
import Testing
@testable import AppFeature
@testable import CaptureKit

/// Here rather than next to the other ScreenRecorder tests: it reuses `TestVideo`.
@Suite("Recording segments")
struct RecordingJoinTests {
    private func out() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-joined.mp4")
    }

    private func seconds(_ url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    private func isH264(_ url: URL) async throws -> Bool {
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        let formats = try await track.load(.formatDescriptions)
        return !formats.isEmpty && formats.allSatisfy { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 }
    }

    @Test("Two and three segments join back to back, still H.264, segments gone", arguments: [[1.0, 2.0], [1.0, 0.5, 1.5]])
    func joins(_ lengths: [Double]) async throws {
        var segments: [URL] = []
        for length in lengths { segments.append(try await TestVideo.make(seconds: length, width: 320, height: 240, fps: 30)) }
        let url = try await ScreenRecorder.join(segments, into: out())
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(abs(try await seconds(url) - lengths.reduce(0, +)) < 0.1)
        #expect(try await isH264(url))
        #expect(segments.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test("One segment is moved as is")
    func oneIsMoved() async throws {
        let segment = try await TestVideo.make(seconds: 1, width: 320, height: 240, fps: 30)
        let bytes = try Data(contentsOf: segment)
        let url = try await ScreenRecorder.join([segment], into: out())
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try Data(contentsOf: url) == bytes)
        #expect(!FileManager.default.fileExists(atPath: segment.path))
    }

    @Test("Empty segments are skipped; all empty is “stopped too soon”")
    func emptySkipped() async throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: empty.path, contents: Data())
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        let a = try await TestVideo.make(seconds: 1, width: 320, height: 240, fps: 30)
        let b = try await TestVideo.make(seconds: 1, width: 320, height: 240, fps: 30)
        let url = try await ScreenRecorder.join([a, empty, missing, b], into: out())
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(abs(try await seconds(url) - 2) < 0.1)
        #expect(!FileManager.default.fileExists(atPath: empty.path))

        let empty2 = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: empty2.path, contents: Data())
        await #expect(throws: (any Error).self) { try await ScreenRecorder.join([empty2, missing], into: out()) }
        #expect(!FileManager.default.fileExists(atPath: empty2.path))

        // Not empty but no video in it: kept when nothing could be joined (it may be all there is).
        let junk = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: junk.path, contents: Data("not a movie".utf8))
        defer { try? FileManager.default.removeItem(at: junk) }
        await #expect(throws: (any Error).self) { try await ScreenRecorder.join([junk], into: out()) }
        #expect(FileManager.default.fileExists(atPath: junk.path))
    }
}

@Suite("Recorded time")
@MainActor
struct RecordedTimeTests {
    @Test("Pauses aren't counted")
    func pausesLeftOut() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var clock = RecordedTime()
        #expect(clock.elapsed(at: t0) == 0)
        clock.run(at: t0)
        #expect(clock.elapsed(at: t0 + 5) == 5)
        clock.pause(at: t0 + 10)
        #expect(clock.elapsed(at: t0 + 60) == 10) // stopped while paused
        clock.pause(at: t0 + 70) // twice: no change
        clock.run(at: t0 + 100)
        clock.run(at: t0 + 110) // twice: keeps the first start
        #expect(clock.elapsed(at: t0 + 115) == 25)
        #expect(RecordingController.elapsed(clock.elapsed(at: t0 + 165)) == "01:15")
    }
}
