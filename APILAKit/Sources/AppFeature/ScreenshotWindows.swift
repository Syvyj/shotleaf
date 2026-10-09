import AppKit
import Core
import SwiftUI

/// Opens screenshot preview windows and pinned screenshots. Each capture gets
/// its own window, so several can be open (and pinned) at once.
@MainActor
final class ScreenshotWindows {
    /// OCR / ask-AI hand-off to the panel.
    var onText: (ImagePayload) -> Void = { _ in }
    var onAsk: (ImagePayload) -> Void = { _ in }

    private(set) var open: [ObjectIdentifier: FloatingPanel] = [:] // internal for tests

    func show(_ payload: ImagePayload) {
        guard let image = NSImage(data: payload.data) else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let scale = screen?.backingScaleFactor ?? 2
        let pixels = CGSize(width: payload.width, height: payload.height)
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        // Leave room for the header, toolbar and hints around the image.
        let margin = 2 * ScreenshotView.margin
        let room = CGSize(width: visible.width - 80 - margin, height: visible.height - Self.chromeHeight - margin)
        let display = Self.fit(points: CGSize(width: pixels.width / scale, height: pixels.height / scale), in: room)
        guard let cgImage = NSBitmapImageRep(data: payload.data)?.cgImage else { return }
        let doc = AnnotationDocument()

        /// The shot with its marks (or the untouched original), as PNG.
        let result: () -> Data = {
            let picture = doc.base?.image ?? cgImage
            let size = doc.base?.size ?? display
            guard !doc.isEmpty || doc.base != nil,
                  let composed = AnnotationRenderer.export(picture, imageSize: size, items: doc.items),
                  let png = NSBitmapImageRep(cgImage: composed).representation(using: .png, properties: [:])
            else { return payload.data }
            return png
        }

        var panel: FloatingPanel!
        let close: () -> Void = { [weak self] in self?.close(panel) }
        let actions = ScreenshotActions(
            copy: { Self.copy(result()) },
            save: { Self.save(result()) },
            pin: { [weak self] in
                let png = result()
                guard let pinned = NSImage(data: png), let rep = NSBitmapImageRep(data: png) else { return }
                close()
                self?.pin(pinned, size: CGSize(width: CGFloat(rep.pixelsWide) / scale, height: CGFloat(rep.pixelsHigh) / scale), data: png)
            },
            text: { [weak self] in                                                // OCR the clean picture (cropped, if applied)
                close()
                let picture = doc.base.flatMap { NSBitmapImageRep(cgImage: $0.image).representation(using: .png, properties: [:]) }
                self?.onText(picture.map(Self.payload) ?? payload)
            },
            ask: { [weak self] in close(); self?.onAsk(Self.payload(result())) },  // marks help the model
            close: close,
            dragFile: { Self.writeTempPNG(result()) }
        )
        let width = max(display.width + margin, ScreenshotView.minContentWidth) + 28
        panel = makePanel(ScreenshotView(image: image, cgImage: cgImage, pixelSize: pixels, displaySize: display, actions: actions, doc: doc),
                          proposedWidth: width, resizable: true)
        panel.setFrameOrigin(Self.placed(panel.frame.size, centeredIn: visible))
        present(panel)
    }

    /// A small "3… 2… 1" badge near the top of the screen. It never reaches
    /// the shot: the picker leaves APILA's own windows out.
    func countdown(_ seconds: Int) async {
        let model = Countdown(left: seconds)
        let panel = makePanel(CountdownBadge(model: model))
        panel.ignoresMouseEvents = true
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - panel.frame.width / 2,
                                         y: screen.visibleFrame.maxY - panel.frame.height - 24))
        }
        panel.orderFrontRegardless() // not key: the user is busy opening a menu
        while model.left > 0 {
            try? await Task.sleep(for: .seconds(1))
            model.left -= 1
        }
        panel.orderOut(nil)
    }

    static func payload(_ png: Data) -> ImagePayload {
        let rep = NSBitmapImageRep(data: png)
        return ImagePayload(data: png, width: rep?.pixelsWide ?? 0, height: rep?.pixelsHigh ?? 0)
    }

    private func pin(_ image: NSImage, size: CGSize, data: Data) {
        // Pinned copies start at their real size, capped so they don't cover the screen.
        let size = Self.fit(points: size, in: CGSize(width: 900, height: 700))
        var panel: FloatingPanel!
        panel = makePanel(PinnedScreenshotView(
            image: image, size: size,
            copy: { Self.copy(data) },
            close: { [weak self] in self?.close(panel) }
        ))
        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2))
        present(panel)
    }

    // MARK: Windows

    /// `proposedWidth` + `resizable`: the window opens at that width and the
    /// smallest height the view allows, and can only grow from there.
    private func makePanel<V: View>(_ view: V, proposedWidth: CGFloat? = nil, resizable: Bool = false) -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: .zero,
            // No system .resizable: it ignored our minimum; our grips/edges resize.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        // Ask SwiftUI for the ideal size up front: a fresh hosting view reports
        // 0×0 until it's on screen, and placing a 0×0 window centres it wrong.
        let controller = NSHostingController(rootView: view)
        // Height 0 asks for the view's minimum height at that width.
        let size = controller.sizeThatFits(in: NSSize(width: proposedWidth ?? 10_000, height: proposedWidth == nil ? 10_000 : 0))
        controller.sizingOptions = [] // we size the window ourselves, once
        panel.contentViewController = controller
        panel.setContentSize(size)
        if resizable { panel.minimumSize = size }
        return panel
    }

    private func present(_ panel: FloatingPanel) {
        open[ObjectIdentifier(panel)] = panel
        panel.makeKeyAndOrderFront(nil)
    }

    private func close(_ panel: FloatingPanel?) {
        guard let panel else { return }
        panel.orderOut(nil)
        open[ObjectIdentifier(panel)] = nil
    }

    // MARK: Files & clipboard

    static func copy(_ png: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
    }

    /// Saves to the Desktop as "APILA 2026-10-08 at 16.50.12.png".
    static func save(_ png: Data, to folder: URL? = nil, now: Date = Date()) -> URL? {
        let folder = folder ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let url = folder.appendingPathComponent(fileName(now))
        return (try? png.write(to: url)) != nil ? url : nil
    }

    static func fileName(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "APILA \(f.string(from: date)).png"
    }

    /// ponytail: temp files stay until macOS cleans the temp dir — a drop target
    /// may read the file lazily, so deleting on close could break the drop.
    private static func writeTempPNG(_ png: Data) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName(Date()))
        try? png.write(to: url)
        return url
    }

    // MARK: Geometry

    /// Header + action row + padding, in points (the canvas margin is extra).
    static let chromeHeight: CGFloat = 190

    /// Scales `points` down (never up) to fit `available` (tall captures shrink
    /// to the screen height, wide ones to its width).
    static func fit(points: CGSize, in available: CGSize) -> CGSize {
        let k = min(1, available.width / max(points.width, 1), available.height / max(points.height, 1))
        return CGSize(width: (points.width * k).rounded(), height: (points.height * k).rounded())
    }

    /// Centered in `frame`, but never sticking out of it.
    static func placed(_ size: CGSize, centeredIn frame: CGRect) -> NSPoint {
        let x = min(max(frame.midX - size.width / 2, frame.minX + 8), frame.maxX - size.width - 8)
        let y = min(max(frame.midY - size.height / 2, frame.minY + 8), frame.maxY - size.height - 8)
        return NSPoint(x: max(x, frame.minX), y: max(y, frame.minY))
    }
}

@MainActor @Observable
final class Countdown {
    var left: Int
    init(left: Int) { self.left = left }
}

private struct CountdownBadge: View {
    let model: Countdown
    var body: some View {
        HStack(spacing: 8) {
            BrandLogo(size: 18)
            Text(verbatim: "\(model.left)")
                .font(Leaf.font(22, .bold)).monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: model.left)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .background(Leaf.surface, in: Capsule())
    }
}
