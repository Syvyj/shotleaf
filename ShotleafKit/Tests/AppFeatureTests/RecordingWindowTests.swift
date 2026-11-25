import AppKit
import AVFoundation
import Testing
@testable import AppFeature

extension SharedState {
    @Suite("Recording window")
    @MainActor
    struct RecordingWindowTests {
        private func clip(_ model: RecordingModel) {
            model.range = CMTimeRange(start: CMTime(seconds: 0.5, preferredTimescale: 600), duration: CMTime(seconds: 1, preferredTimescale: 600))
        }

        private func pastedFile() -> URL? {
            (NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL])?.first
        }

        @Test func copyPutsMP4FileOnPasteboard() async throws {
            let video = try await TestVideo.make(seconds: 2, width: 320, height: 240, fps: 30)
            let model = RecordingModel(original: video)
            await model.load()
            clip(model)
            try await model.copy()
            let file = try #require(pastedFile())
            #expect(file.pathExtension == "mp4")
            #expect(file != video) // trimmed into a new file
            #expect(NSPasteboard.general.types?.contains(ClipboardHistory.ownType) == true) // no dead history entry
            #expect(FileManager.default.fileExists(atPath: file.path))
        }

        @Test func changingLimitKeepsOriginal() async throws {
            let video = try await TestVideo.make(seconds: 2, width: 320, height: 240, fps: 30)
            let model = RecordingModel(original: video)
            await model.load()
            clip(model)
            model.limit = 8_000_000
            let small = try await model.current()
            let size = try small.resourceValues(forKeys: [URLResourceKey.fileSizeKey]).fileSize
            #expect(size.map { $0 <= 8_000_000 } == true)
            model.limit = nil
            let trimmed = try await model.current()
            #expect(trimmed != video)
            let seconds = try await AVURLAsset(url: trimmed).load(.duration).seconds
            #expect(abs(seconds - 1) < 0.2)
            #expect(FileManager.default.fileExists(atPath: video.path))
            #expect(try await model.current() == trimmed) // cached: not encoded again
        }

        @Test func limitBelowTheTrimReencodes() async throws {
            let video = try await TestVideo.make(seconds: 2, width: 1600, height: 1000, fps: 30) // big enough to need a fit
            let model = RecordingModel(original: video)
            await model.load()
            clip(model)
            let trimmed = try await model.current()
            let trimmedSize = try #require(trimmed.resourceValues(forKeys: [URLResourceKey.fileSizeKey]).fileSize)
            let limit = trimmedSize / 2
            model.limit = limit
            let small = try await model.current()
            #expect(small != trimmed)
            let size = try #require(small.resourceValues(forKeys: [URLResourceKey.fileSizeKey]).fileSize)
            #expect(size <= limit)
            model.limit = nil
            #expect(try await model.current() == trimmed)
        }

        @Test func limitOutOfReachIsTooLong() async throws {
            let video = try await TestVideo.make(seconds: 2, width: 320, height: 240, fps: 30)
            let model = RecordingModel(original: video)
            await model.load()
            model.limit = 500
            await #expect(throws: VideoEditError.tooLong) { try await model.current() }
        }

        @Test func cancelledCopyLeavesTheClipboard() async throws {
            let video = try await TestVideo.make(seconds: 2, width: 320, height: 240, fps: 30)
            let model = RecordingModel(original: video)
            await model.load()
            clip(model)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("keep", forType: .string)
            let copy = Task { try await model.copy() } // the window closed while it encoded
            copy.cancel()
            await #expect(throws: (any Error).self) { try await copy.value }
            #expect(NSPasteboard.general.string(forType: .string) == "keep")
        }

        @Test func untrimmedOriginalIsUsedAsIs() async throws {
            let video = try await TestVideo.make(seconds: 1, width: 320, height: 240, fps: 30)
            let model = RecordingModel(original: video)
            await model.load()
            #expect(try await model.current() == video)
        }

        @Test func closingWindowKeepsFiles() async throws {
            let video = try await TestVideo.make(seconds: 2, width: 320, height: 240, fps: 30)
            let windows = ScreenshotWindows()
            let model = await windows.showRecording(video)
            clip(model)
            try await model.copy()
            let file = try #require(pastedFile())
            let panel = try #require(windows.open.values.first)
            windows.close(panel)
            #expect(windows.open.isEmpty)
            #expect(FileManager.default.fileExists(atPath: file.path))
            #expect(FileManager.default.fileExists(atPath: video.path))
        }

        @Test func trimKeepsHalfASecond() {
            #expect(TrimBar.clamped(start: 3, end: 3.25, duration: 10, moving: .start) == (2.75, 3.25))
            #expect(TrimBar.clamped(start: 3, end: 3.25, duration: 10, moving: .end) == (3, 3.5))
            #expect(TrimBar.clamped(start: -1, end: 12, duration: 10, moving: .end) == (0, 10))
            #expect(TrimBar.clamped(start: 0, end: 0.1, duration: 0.3, moving: .end) == (0, 0.3)) // shorter than the minimum
        }
    }
}
