import AppKit

/// What's on screen while recording, in the capture overlay's look: the frame just
/// outside the area and a capsule with the time, Pause/Resume, Stop and Cancel.
/// Both are borderless panels; pass their window numbers to `ScreenRecorder.start`.
@MainActor
public enum RecordingChrome {
    /// How far the frame's ring reaches outside the area.
    static let ring: CGFloat = 4
    /// Room for the glow around the ring.
    static let margin: CGFloat = 20

    /// The frame around `area` (Cocoa global points). Nothing of it falls inside the
    /// area; the mouse passes through.
    public static func frame(around area: CGRect) -> NSPanel {
        let panel = overlayPanel(area.insetBy(dx: -margin, dy: -margin))
        panel.ignoresMouseEvents = true
        panel.contentView = FrameView(area: CGRect(x: margin, y: margin, width: area.width, height: area.height))
        return panel
    }

    /// Where the capsule goes: centred 8 pt under the frame; above it when that's off
    /// `visible`; else inside the area near its bottom. Always within `visible` sideways.
    public static func placement(_ size: CGSize, area: CGRect, visible: CGRect) -> CGRect {
        let frame = area.insetBy(dx: -ring, dy: -ring), gap: CGFloat = 8
        var y = frame.minY - gap - size.height
        if y < visible.minY { y = frame.maxY + gap }
        if y + size.height > visible.maxY { y = max(area.minY, visible.minY) + gap }
        let x = min(max(area.midX - size.width / 2, visible.minX), visible.maxX - size.width)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    static func overlayPanel(_ rect: CGRect) -> NSPanel {
        let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }
}

private final class FrameView: NSView {
    private let area: CGRect

    init(area: CGRect) {
        self.area = area
        super.init(frame: area.insetBy(dx: -RecordingChrome.margin, dy: -RecordingChrome.margin))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        // Everything outside the area only: the glow would spill inward.
        let outside = NSBezierPath(rect: bounds)
        outside.append(NSBezierPath(rect: area))
        outside.windingRule = .evenOdd
        outside.addClip()
        CaptureStyle.drawFrame(area.insetBy(dx: -2, dy: -2), ringWidth: 2)
    }
}

/// The capsule: `● mm:ss`, Pause/Resume, Stop, Cancel. Clicks don't take focus from
/// the app being recorded.
@MainActor
public final class RecordingControls {
    public let panel: NSPanel
    public var onPauseResume: () -> Void = {}
    public var onStop: () -> Void = {}
    public var onCancel: () -> Void = {}

    private let dot = NSView()
    private let time = NSTextField(labelWithString: "00:00")
    private let pauseButton = FirstClickButton()

    public init() {
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        time.font = CaptureStyle.mono(13)
        time.textColor = .white
        let stop = FirstClickButton(), cancel = FirstClickButton()
        Self.style(stop, "stop.fill", String(localized: "Stop Recording"))
        Self.style(cancel, "xmark", String(localized: "Cancel Recording"))
        for button in [pauseButton, stop, cancel] { button.widthAnchor.constraint(equalToConstant: 18).isActive = true }

        let stack = NSStackView(views: [dot, time, pauseButton, stop, cancel])
        stack.spacing = 10
        stack.setCustomSpacing(6, after: dot)
        stack.setCustomSpacing(14, after: time)
        stack.edgeInsets = NSEdgeInsets(top: 7, left: 14, bottom: 7, right: 12)
        stack.wantsLayer = true
        stack.layer?.backgroundColor = CaptureStyle.capsule.cgColor
        stack.layer?.borderColor = CaptureStyle.capsuleStroke.cgColor
        stack.layer?.borderWidth = 1
        let size = stack.fittingSize
        stack.layer?.cornerRadius = size.height / 2

        panel = RecordingChrome.overlayPanel(CGRect(origin: .zero, size: size))
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = stack
        pauseButton.target = self
        pauseButton.action = #selector(pauseResume)
        stop.target = self
        stop.action = #selector(stopTapped)
        cancel.target = self
        cancel.action = #selector(cancelTapped)
        show(time: "00:00", paused: false)
    }

    /// Puts the capsule by `area` (Cocoa global points) on a screen with `visible` frame.
    public func place(around area: CGRect, in visible: CGRect) {
        panel.setFrame(RecordingChrome.placement(panel.frame.size, area: area, visible: visible), display: false)
    }

    public func show(time text: String, paused: Bool) {
        time.stringValue = text
        dot.layer?.backgroundColor = (paused ? NSColor.systemGray : NSColor.systemRed).cgColor
        Self.style(pauseButton, paused ? "play.fill" : "pause.fill", paused ? String(localized: "Resume") : String(localized: "Pause"))
    }

    @objc private func pauseResume() { onPauseResume() }
    @objc private func stopTapped() { onStop() }
    @objc private func cancelTapped() { onCancel() }

    private static func style(_ button: NSButton, _ symbol: String, _ title: String) {
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        button.contentTintColor = .white
        button.toolTip = title
        button.setAccessibilityLabel(title)
    }
}

/// Works on the first click while another app is active.
private final class FirstClickButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
