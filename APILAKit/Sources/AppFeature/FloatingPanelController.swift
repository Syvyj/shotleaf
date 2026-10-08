import AppKit
import OSLog
import SwiftUI

/// A non-activating panel that can still become key — so it receives keyboard
/// input WITHOUT activating APILA (the source app stays "active", its selection
/// preserved for paste-back).
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Our own floor for the window size. SwiftUI's hosting controller can
    /// reset `contentMinSize`, so the real minimum lives here and
    /// `contentMinSize` (read by the resize grips) never reports less.
    var minimumSize: NSSize = .zero

    override var contentMinSize: NSSize {
        get {
            let system = super.contentMinSize
            return NSSize(width: max(system.width, minimumSize.width), height: max(system.height, minimumSize.height))
        }
        set { super.contentMinSize = newValue }
    }

    /// Every resize path (our grips, code) goes through here, so the minimum
    /// holds no matter who resizes — below it the SwiftUI content would spill
    /// out of the window.
    override func setFrame(_ frame: NSRect, display: Bool) {
        if frame.size != self.frame.size, minimumSize != .zero {
            Logger(subsystem: "app.apila.APILA", category: "resize")
                .notice("resize to \(String(describing: frame.size), privacy: .public) min \(String(describing: self.contentMinSize), privacy: .public)")
        }
        var f = frame
        let min = contentMinSize
        if f.width < min.width {
            // Keep the edge that wasn't dragged in place.
            if f.minX != self.frame.minX { f.origin.x = f.maxX - min.width }
            f.size.width = min.width
        }
        if f.height < min.height {
            if f.maxY == self.frame.maxY { f.origin.y = f.maxY - min.height } else { f.origin.y = f.minY }
            f.size.height = min.height
        }
        super.setFrame(f, display: display)
    }
}

/// Owns the floating panel: a translucent, non-activating `NSPanel` shown near
/// the cursor. The Kerlig-style floating UI.
@MainActor
public final class FloatingPanelController {
    private var panel: FloatingPanel?
    private let content: () -> AnyView

    public init(content: @escaping () -> AnyView) {
        self.content = content
    }

    public func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        positionNearCursor(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    public func hide() {
        panel?.orderOut(nil)
    }

    public func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    private func makePanel() -> FloatingPanel {
        // Borderless: no titlebar, no traffic-light buttons (it's a command
        // palette). Closing is via Esc / the in-panel Close button. canBecomeKey
        // is overridden so it still receives keyboard input.
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true // hover highlight follows the mouse
        // Set explicitly: a non-opaque window otherwise lets clicks on its
        // translucent (material) areas fall through to the app underneath.
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let hosting = NSHostingView(rootView: content())
        hosting.sizingOptions = [.preferredContentSize] // resize panel to fit each screen
        panel.contentView = hosting
        return panel
    }

    private func positionNearCursor(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { panel.center(); return }

        let size = panel.frame.size
        var origin = CGPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 8)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }
}
