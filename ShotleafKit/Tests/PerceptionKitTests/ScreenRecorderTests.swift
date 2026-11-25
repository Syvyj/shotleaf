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
