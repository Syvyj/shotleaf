import AppKit
import SwiftUI

/// Shottr-style drag-out: lies over the shot and, when `wantsDrag(point)` says
/// so (Select mode, nothing under the pointer), turns a mouse drag into a
/// system drag of the whole result — drop it into any app. Otherwise it lets
/// the click through to the annotation canvas underneath.
struct DragOutView: NSViewRepresentable {
    /// Point in image points (the view covers the image exactly, y down).
    var wantsDrag: (CGPoint) -> Bool
    /// Called on mouse-down (e.g. to clear the selection).
    var onPress: () -> Void
    /// The file to hand over, written when the drag starts.
    var file: () -> URL?
    var thumbnail: NSImage

    final class SourceView: NSView, NSDraggingSource {
        var wantsDrag: (CGPoint) -> Bool = { _ in false }
        var onPress: () -> Void = {}
        var file: () -> URL? = { nil }
        var thumbnail = NSImage()
        private var down: NSEvent?

        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = convert(point, from: superview)
            return bounds.contains(local) && wantsDrag(local) ? self : nil
        }

        override func mouseDown(with event: NSEvent) {
            down = event
            onPress()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let down, let url = file() else { return }
            let a = down.locationInWindow, b = event.locationInWindow
            guard hypot(b.x - a.x, b.y - a.y) > 3 else { return }
            self.down = nil
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            // The drag image: the whole shot, scaled down under the pointer.
            let size = Self.dragSize(for: thumbnail.size)
            let p = convert(a, from: nil)
            item.setDraggingFrame(CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height),
                                  contents: thumbnail)
            beginDraggingSession(with: [item], event: down, source: self)
        }

        override func mouseUp(with event: NSEvent) { down = nil }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .copy
        }

        static func dragSize(for size: CGSize) -> CGSize {
            let k = min(1, 220 / max(size.width, size.height, 1))
            return CGSize(width: size.width * k, height: size.height * k)
        }
    }

    func makeNSView(context: Context) -> SourceView { SourceView() }

    func updateNSView(_ view: SourceView, context: Context) {
        view.wantsDrag = wantsDrag
        view.onPress = onPress
        view.file = file
        view.thumbnail = thumbnail
    }
}
