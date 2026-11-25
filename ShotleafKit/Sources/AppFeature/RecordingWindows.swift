import AppKit
import AVFoundation
import Observation

/// A finished recording in its window: the part kept (`range`) and the size it
/// must fit (`limit`, nil = as recorded). The original is never changed; each
/// trim, fit or GIF is a new file, made once per (range, limit).
@MainActor @Observable
final class RecordingModel {
    /// What "Under N MB ▾" offers, in bytes.
    static let limits = [8_000_000, 10_000_000, 25_000_000]

    let original: URL
    /// Seconds (0 until `load`).
    private(set) var duration: Double = 0
    /// In pixels (zero until `load`).
    private(set) var size: CGSize = .zero
    var range = CMTimeRange(start: .zero, duration: .positiveInfinity)
    var limit: Int?
    @ObservationIgnored private var made: [String: URL] = [:]

    init(original: URL, limit: Int? = nil) {
        self.original = original
        self.limit = limit
    }

    /// Reads the length and frame size; the range becomes the whole recording.
    func load() async {
        let asset = AVURLAsset(url: original)
        guard let length = try? await asset.load(.duration) else { return }
        duration = length.seconds
        range = CMTimeRange(start: .zero, duration: length)
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let natural = try? await track.load(.naturalSize) { size = natural }
    }

    /// The file the buttons hand out: the kept part, under the limit if one is set.
    func current() async throws -> URL {
        let range = range, limit = limit
        let trimmed = try await cached("mp4", range) {
            range.start.seconds <= 0 && range.end.seconds >= self.duration ? self.original : try await VideoEdit.trim(self.original, to: range)
        }
        guard let limit else { return trimmed }
        // Already small enough (a short clip usually is): no re-encoding.
        if let bytes = try? trimmed.resourceValues(forKeys: [.fileSizeKey]).fileSize, bytes <= limit { return trimmed }
        return try await cached("mp4 \(limit)", range) { try await VideoEdit.fit(self.original, range: range, under: limit) }
    }

    /// The kept part as a GIF.
    func gif() async throws -> URL {
        let range = range
        return try await cached("gif", range) { try await VideoEdit.gif(self.original, range: range) }
    }

    func copy() async throws { Self.copy(try await current()) }
    func copyGIF() async throws { Self.copy(try await gif()) }

    /// Into the screenshots folder from Settings, named like a screenshot; nil if it couldn't be written (said in an alert).
    func save() async throws -> URL? {
        let file = try await current()
        let folder = ScreenshotWindows.saveFolder
        let name = (ScreenshotWindows.fileName(Date(), template: ScreenshotWindows.settings.fileNameTemplate) as NSString).deletingPathExtension
        let url = ScreenshotWindows.unused(folder.appendingPathComponent(name).appendingPathExtension(file.pathExtension))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: file, to: url)
            return url
        } catch {
            SaveError.show(error, saving: String(localized: "the recording"))
            return nil
        }
    }

    private func cached(_ kind: String, _ range: CMTimeRange, make: () async throws -> URL) async throws -> URL {
        let key = "\(kind) \(range.start.seconds) \(range.end.seconds)"
        if let url = made[key] { return url }
        let url = try await make()
        made[key] = url
        return url
    }

    /// The file on the clipboard, as Finder copies one: Telegram, Mail and Finder paste it with ⌘V.
    /// Not marked as Shotleaf's own, like a plain screenshot copy: it lands in the clipboard history.
    static func copy(_ file: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        Sound.copied()
    }
}

extension ScreenshotWindows {
    /// The window after a recording stops: preview, trim, copy, drag, save, GIF, fit under a size.
    @discardableResult
    func showRecording(_ url: URL) async -> RecordingModel {
        let stored = Self.settings.smallVideoLimit
        let model = RecordingModel(original: url, limit: stored == 0 ? nil : RecordingModel.limits.contains(stored) ? stored : 8_000_000)
        await model.load()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let scale = screen?.backingScaleFactor ?? 2
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let points = model.size == .zero ? CGSize(width: 640, height: 400) : CGSize(width: model.size.width / scale, height: model.size.height / scale)
        let video = Self.fit(points: points, in: CGSize(width: min(visible.width - 80, 1100), height: visible.height - 220))
        var panel: FloatingPanel!
        let view = RecordingView(model: model, videoSize: video) { [weak self] in self?.close(panel) }
        panel = Self.makePanel(view, proposedWidth: max(video.width, RecordingView.minWidth) + 28)
        panel.setFrameOrigin(Self.placed(panel.frame.size, centeredIn: visible))
        present(panel)
        return model
    }
}
