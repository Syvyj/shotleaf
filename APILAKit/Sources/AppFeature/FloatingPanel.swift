import AppKit
import OSLog

/// A non-activating panel that can still become key — so it receives keyboard
/// input WITHOUT activating APILA (the app the user works in stays active).
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
