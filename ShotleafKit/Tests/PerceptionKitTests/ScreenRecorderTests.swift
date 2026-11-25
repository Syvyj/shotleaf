import Testing
import CoreGraphics
import CoreMedia
@testable import CaptureKit
import ScreenCaptureKit
import Synchronization

@Suite("Screen recording")
struct ScreenRecorderTests {
    @Test("Native pixels, cursor and clicks, no audio, up to 30 fps")
    func recordingConfigUsesNativePixels() {
        let area = RecordingArea(displayID: 1, rect: CGRect(x: 10, y: 20, width: 400, height: 300), scale: 2)
        let config = ScreenRecorder.recordingConfig(for: area)
        #expect(config.width == 800 && config.height == 600)
        #expect(config.sourceRect == area.rect)
        #expect(config.showsCursor && config.showMouseClicks)
        #expect(!config.capturesAudio)
        #expect(config.minimumFrameInterval == CMTime(value: 1, timescale: 30))
    }

    @Test("Odd pixel sizes round up to even (H.264)")
    func oddPixelSizeRoundsToEven() {
        let config = ScreenRecorder.recordingConfig(for: RecordingArea(displayID: 1, rect: CGRect(x: 0, y: 0, width: 401, height: 301), scale: 1))
        #expect(config.width == 402 && config.height == 302)
    }

    @Test("A stream the system ended reports it, so the recording can finish as Stop does")
    func systemEndReported() {
        let count = Mutex(0)
        let ended = StreamEnded { count.withLock { $0 += 1 } }
        let stream = SCStream(filter: SCContentFilter(), configuration: SCStreamConfiguration(), delegate: ended)
        ended.stream(stream, didStopWithError: CocoaError(.userCancelled))
        #expect(count.withLock { $0 } == 1)
    }
}

@Suite("Recording controls placement")
@MainActor
struct RecordingControlsPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875) // visible frame, Cocoa points
    let size = CGSize(width: 200, height: 32)

    @Test("Centred 8 pt under the frame")
    func below() {
        let area = CGRect(x: 400, y: 300, width: 600, height: 400)
        // The frame's ring reaches 4 pt outside the area.
        #expect(RecordingChrome.placement(size, area: area, visible: screen) == CGRect(x: 600, y: 300 - 4 - 8 - 32, width: 200, height: 32))
    }

    @Test("Above when there's no room below")
    func above() {
        let area = CGRect(x: 400, y: 20, width: 600, height: 400)
        #expect(RecordingChrome.placement(size, area: area, visible: screen) == CGRect(x: 600, y: 420 + 4 + 8, width: 200, height: 32))
    }

    @Test("Inside near the bottom when neither fits")
    func inside() {
        #expect(RecordingChrome.placement(size, area: screen, visible: screen) == CGRect(x: 620, y: 8, width: 200, height: 32))
        // A full-screen area reaching under the Dock: still within the visible frame.
        let full = CGRect(x: 0, y: 0, width: 1440, height: 900), visible = CGRect(x: 0, y: 70, width: 1440, height: 805)
        #expect(RecordingChrome.placement(size, area: full, visible: visible).minY == 78)
    }

    @Test("Clamped to the screen's edges")
    func clamped() {
        let left = CGRect(x: 0, y: 300, width: 100, height: 100), right = CGRect(x: 1380, y: 300, width: 60, height: 100)
        #expect(RecordingChrome.placement(size, area: left, visible: screen).minX == 0)
        #expect(RecordingChrome.placement(size, area: right, visible: screen).maxX == 1440)
    }
}
