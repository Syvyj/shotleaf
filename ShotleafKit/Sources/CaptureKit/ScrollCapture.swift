import AppKit
import Core
import ScreenCaptureKit
import SwiftUI

/// Scrolling screenshot: pick an area, then scroll it while Shotleaf films it
/// and glues the frames (`ScrollStitcher`). Done / ↩ finishes, Esc cancels.
/// Shotleaf's own windows (the frame and the control bar) never get filmed.
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

/// A green frame around the area being filmed, and a capsule under it with
/// the progress and Cancel / Done, in the capture overlay's style. Takes ↩ and
/// Esc without activating Shotleaf, so the app being scrolled stays in front.
@MainActor
private final class ScrollControlBar {
    typealias Outcome = ScrollBarModel.Outcome
    private let model = ScrollBarModel()
    var outcome: Outcome? { model.outcome }
    var status: String {
        get { model.status }
        set { guard newValue != model.status else { return }; model.status = newValue; fit() }
    }

    private let frameWindow: NSPanel
    private let barWindow: KeyPanel
    private let hosting: NSHostingView<ScrollBarView>
    private let area: CGRect
    private let screen: NSScreen

    init(around area: CGRect, on screen: NSScreen) {
        self.area = area
        self.screen = screen
        frameWindow = NSPanel(contentRect: area.insetBy(dx: -3, dy: -3), styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        frameWindow.isOpaque = false
        frameWindow.backgroundColor = .clear
        frameWindow.ignoresMouseEvents = true // scrolling goes straight through
        frameWindow.level = .floating
        frameWindow.hasShadow = false
        frameWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        frameWindow.contentView = FrameView()

        hosting = NSHostingView(rootView: ScrollBarView(model: model))
        barWindow = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        barWindow.isOpaque = false
        barWindow.backgroundColor = .clear
        barWindow.level = .floating
        barWindow.hasShadow = false // the capsule draws its own
        barWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        barWindow.contentView = hosting
        fit()

        frameWindow.orderFrontRegardless()
        barWindow.makeKeyAndOrderFront(nil)
    }

    /// The bar hugs its content, centred under the area (or above it, if
    /// there's no room below), always on screen.
    private func fit() {
        let size = hosting.fittingSize
        let visible = screen.visibleFrame
        let below = area.minY - size.height - 10
        let y = below >= visible.minY ? below : min(area.maxY + 10, visible.maxY - size.height)
        let x = min(max(area.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        barWindow.setFrame(CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height), display: true)
    }

    func close() {
        frameWindow.orderOut(nil)
        barWindow.orderOut(nil)
    }

    private final class FrameView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 4, yRadius: 4)
            path.lineWidth = 3
            path.setLineDash([8, 5], count: 2, phase: 0)
            CaptureStyle.lime.setStroke()
            path.stroke()
        }
    }
}

@MainActor
@Observable
final class ScrollBarModel {
    enum Outcome { case done, cancel }
    var status = String(localized: "Scroll down slowly")
    var outcome: Outcome?
}

/// Dark leaf-glass capsule: a live dot, the progress, esc / ↩ buttons.
struct ScrollBarView: View {
    let model: ScrollBarModel
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(nsColor: CaptureStyle.lime))
                .frame(width: 8, height: 8)
                .opacity(pulse ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.8).repeatForever(), value: pulse)
                .onAppear { pulse = true }
            Text(model.status)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .fixedSize()
                .padding(.trailing, 4)
            Button { model.outcome = .cancel } label: {
                key("Cancel", "esc", prominent: false)
            }
            .keyboardShortcut(.cancelAction)
            Button { model.outcome = .done } label: {
                key("Done", "↩", prominent: true)
            }
            .keyboardShortcut(.defaultAction)
        }
        .buttonStyle(.plain)
        .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 6)
        .background(Capsule().fill(Color(nsColor: CaptureStyle.capsule)))
        .overlay(Capsule().strokeBorder(Color(nsColor: CaptureStyle.capsuleStroke)))
        .padding(10) // room for the shadow inside the window
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        .fixedSize()
    }

    private func key(_ title: LocalizedStringKey, _ cap: String, prominent: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(cap).font(.system(size: 10.5, weight: .bold, design: .rounded)).opacity(0.6)
        }
        .foregroundStyle(prominent ? Color(red: 0.07, green: 0.1, blue: 0.07) : .white)
        .padding(.horizontal, 12).frame(height: 28)
        .background {
            Capsule().fill(prominent
                ? AnyShapeStyle(LinearGradient(colors: [Color(nsColor: CaptureStyle.leaf), Color(nsColor: CaptureStyle.lime)],
                                               startPoint: .leading, endPoint: .trailing))
                : AnyShapeStyle(Color.white.opacity(0.12)))
        }
        .contentShape(Capsule())
    }
}

/// Borderless panels can't become key by default — the bar needs ↩ / Esc.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
