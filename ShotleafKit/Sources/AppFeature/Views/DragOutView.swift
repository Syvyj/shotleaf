import AppKit
import OSLog
import SwiftUI

private let log = Logger(subsystem: "dev.syvyj.shotleaf", category: "drag")

/// Drag-out: lies over the shot and, when `wantsDrag(point)` says
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
            log.notice("dragout mouseDown at \(String(describing: self.convert(event.locationInWindow, from: nil)), privacy: .public) bounds \(String(describing: self.bounds), privacy: .public)")
            down = event
            onPress()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let down, let url = file() else { log.notice("dragout drag ignored: down=\(self.down != nil, privacy: .public)"); return }
            let a = down.locationInWindow, b = event.locationInWindow
            guard hypot(b.x - a.x, b.y - a.y) > 3 else { return }
            self.down = nil
            let item = NSDraggingItem(pasteboardWriter: ShotPromise(file: url))
            // The drag image: the whole shot, scaled down under the pointer.
            let size = Self.dragSize(for: thumbnail.size)
            let p = convert(a, from: nil)
            item.setDraggingFrame(CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height),
                                  contents: thumbnail)
            let session = beginDraggingSession(with: [item], event: down, source: self)
            log.notice("dragout session started \(session.draggingSequenceNumber, privacy: .public) file \(url.lastPathComponent, privacy: .public)")
        }

        override func mouseUp(with event: NSEvent) { down = nil }

        // The open hand says "you can drag this out". This view sits on top, so
        // it owns the cursor over the shot (cursor rects need the active app).
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }

        override func mouseMoved(with event: NSEvent) {
            if wantsDrag(convert(event.locationInWindow, from: nil)) { NSCursor.openHand.set() }
        }

        override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .copy
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            log.notice("dragout session ended operation \(operation.rawValue, privacy: .public)")
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

/// What the drag carries. Finder wants a *file promise* (it picks where to
/// write); chat apps and most others take a plain file URL. This provides both.
final class ShotPromise: NSFilePromiseProvider, NSFilePromiseProviderDelegate {
    let file: URL

    init(file: URL) {
        self.file = file
        super.init()
        fileType = "public.png"
        delegate = self
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + [.fileURL]
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .fileURL ? (file as NSURL).pasteboardPropertyList(forType: .fileURL) : super.pasteboardPropertyList(forType: type)
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        file.lastPathComponent
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        do {
            try FileManager.default.copyItem(at: file, to: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}
