import AppKit
import Core
import ScreenCaptureKit

/// Scrolling screenshot: pick an area, then scroll it while APILA films it
/// and glues the frames (`ScrollStitcher`). Done / ↩ finishes, Esc cancels.
/// APILA's own windows (the frame and the control bar) never get filmed.
@MainActor
final class ScrollCapture {
    static let shared = ScrollCapture()
    private var running = false

    func run() async throws -> CGImage {
        try await film(RegionPicker.shared.pickArea())
    }

    /// Films an already picked area until Done / Esc.
    func film(_ area: RegionPicker.Picked) async throws -> CGImage {
        guard !running else { throw AppError.cancelled }
        running = true
        defer { running = false }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw AppError.permissionDenied("Screen Recording")
        }
        guard let display = content.displays.first(where: { $0.displayID == area.displayID }) else {
            throw AppError.missingContext("No screen to capture")
        }
        let scale = area.screen.backingScaleFactor
        let filter = SCContentFilter(display: display, excludingApplications: content.applications.filter { $0.processID == getpid() },
                                     exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = area.rect // display points, top-left origin — same as the picker's
        config.width = Int((area.rect.width * scale).rounded())
        config.height = Int((area.rect.height * scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best

        let screenRect = CGRect(x: area.screen.frame.minX + area.rect.minX, y: area.screen.frame.maxY - area.rect.maxY,
                                width: area.rect.width, height: area.rect.height)
        let bar = ScrollControlBar(around: screenRect, on: area.screen)
        defer { bar.close() }

        var stitcher = ScrollStitcher(width: config.width, height: config.height)
        while bar.outcome == nil {
            let shot = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            guard bar.outcome == nil, let frame = Self.rgba(shot, width: config.width, height: config.height) else { break }
            switch stitcher.add(frame) {
            case .first, .still, .added: bar.status = String(localized: "Scroll down slowly · \(stitcher.stitchedHeight) px")
            case .lost: bar.status = String(localized: "Too fast — scroll back up a little")
            case .full: bar.status = String(localized: "Maximum length reached — press Done")
            }
            try? await Task.sleep(for: .milliseconds(60))
        }
        guard bar.outcome == .done, let image = stitcher.image() else { throw AppError.cancelled }
        return image
    }

    /// The frame as tightly packed sRGB RGBA bytes of a fixed size.
    private static func rgba(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? bytes : nil
    }
}

/// A green frame around the area being filmed, and a bar under it with the
/// progress and Done / Cancel. Takes ↩ and Esc without activating APILA, so
/// the app being scrolled stays in front.
@MainActor
private final class ScrollControlBar {
    enum Outcome { case done, cancel }
    private(set) var outcome: Outcome?
    var status = "" { didSet { label.stringValue = status } }

    private let frameWindow: NSPanel
    private let barWindow: KeyPanel
    private let label = NSTextField(labelWithString: String(localized: "Scroll down slowly"))

    init(around area: CGRect, on screen: NSScreen) {
        frameWindow = NSPanel(contentRect: area.insetBy(dx: -3, dy: -3), styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        frameWindow.isOpaque = false
        frameWindow.backgroundColor = .clear
        frameWindow.ignoresMouseEvents = true // scrolling goes straight through
        frameWindow.level = .floating
        frameWindow.hasShadow = false
        frameWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        frameWindow.contentView = FrameView()

        let size = CGSize(width: 420, height: 44)
        let below = area.minY - size.height - 12
        let y = below >= screen.visibleFrame.minY ? below : min(area.maxY + 12, screen.visibleFrame.maxY - size.height)
        let x = min(max(area.midX - size.width / 2, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        barWindow = KeyPanel(contentRect: CGRect(origin: CGPoint(x: x, y: y), size: size), styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        barWindow.isOpaque = false
        barWindow.backgroundColor = .clear
        barWindow.level = .floating
        barWindow.hasShadow = true
        barWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        barWindow.contentView = makeBar(size: size)

        frameWindow.orderFrontRegardless()
        barWindow.makeKeyAndOrderFront(nil)
    }

    private func makeBar(size: CGSize) -> NSView {
        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = size.height / 2

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        let done = NSButton(title: String(localized: "Done") + "  ↩", target: self, action: #selector(doneTapped))
        done.keyEquivalent = "\r"
        done.bezelStyle = .rounded
        let cancel = NSButton(title: String(localized: "Cancel") + "  esc", target: self, action: #selector(cancelTapped))
        cancel.keyEquivalent = "\u{1b}"
        cancel.bezelStyle = .rounded
        let row = NSStackView(views: [label, cancel, done])
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 8)
        row.frame = background.bounds
        row.autoresizingMask = [.width, .height]
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        background.addSubview(row)
        return background
    }

    @objc private func doneTapped() { outcome = .done }
    @objc private func cancelTapped() { outcome = .cancel }

    func close() {
        frameWindow.orderOut(nil)
        barWindow.orderOut(nil)
    }

    private final class FrameView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 4, yRadius: 4)
            path.lineWidth = 3
            path.setLineDash([8, 5], count: 2, phase: 0)
            NSColor(srgbRed: 0.79, green: 0.91, blue: 0.42, alpha: 1).setStroke() // lime
            path.stroke()
        }
    }
}

/// Borderless panels can't become key by default — the bar needs ↩ / Esc.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
