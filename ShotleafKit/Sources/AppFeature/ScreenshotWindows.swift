import AppKit
import Core
import SettingsKit
import SwiftUI
import UniformTypeIdentifiers

/// Opens screenshot preview windows and pinned screenshots. Each capture gets
/// its own window, so several can be open (and pinned) at once.
@MainActor
final class ScreenshotWindows {
    private(set) var open: [ObjectIdentifier: FloatingPanel] = [:] // internal for tests
    /// "To Snippets": keeps a PNG as a snippet; the folder's name, if it went into one.
    var toSnippets: (Data) -> String? = { _ in nil }

    /// `edited` gets the shot as marked up — on copy and when the window closes —
    /// so its clipboard-history entry shows what was actually made.
    func show(_ payload: ImagePayload, sound: Bool = true, edited: ((Data) -> Void)? = nil) {
        guard let image = NSImage(data: payload.data) else { return }
        if sound { Sound.shutter() }
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
            guard !doc.isEmpty || doc.base != nil || doc.backdrop != nil || doc.watermark != nil,
                  var composed = AnnotationRenderer.export(picture, imageSize: size, items: doc.items,
                                                           canvas: doc.base?.cutOut == true ? .clear : .white, watermark: doc.watermark)
            else { return payload.data }
            if let backdrop = doc.backdrop,
               let framed = backdrop.framed(composed, scale: CGFloat(picture.width) / size.width) { composed = framed }
            return NSBitmapImageRep(cgImage: composed).representation(using: .png, properties: [:]) ?? payload.data
        }

        var panel: FloatingPanel!
        let report: () -> Void = {
            guard let edited else { return }
            let png = result()
            if png != payload.data { edited(png) }
        }
        let close: () -> Void = { [weak self] in report(); self?.close(panel) }
        let actions = ScreenshotActions(
            copy: {
                let png = result()
                Self.copy(png, own: edited != nil) // already in the history: no second entry
                if png != payload.data { edited?(png) }
            },
            save: { Self.save(result(), scale: scale) },
            pin: { [weak self] in
                let png = result()
                guard let pinned = NSImage(data: png), let rep = NSBitmapImageRep(data: png) else { return }
                close()
                self?.pin(pinned, size: CGSize(width: CGFloat(rep.pixelsWide) / scale, height: CGFloat(rep.pixelsHigh) / scale), data: png)
            },
            close: close,
            dragFile: { Self.writeTempPNG(result()) },
            saveAs: { type in
                let ask = NSSavePanel()
                ask.allowedContentTypes = [type]
                ask.directoryURL = Self.saveFolder
                ask.nameFieldStringValue = (Self.fileName(Date(), template: Self.settings.fileNameTemplate) as NSString).deletingPathExtension
                ask.beginSheetModal(for: panel) { response in
                    let png = Self.settings.saveAt1x ? Self.oneX(result(), scale: scale) : result()
                    guard response == .OK, let url = ask.url,
                          let data = Self.encoded(png, as: type, scale: Self.settings.saveAt1x ? 1 : scale) else { return }
                    do { try data.write(to: url) } catch { SaveError.show(error, saving: String(localized: "the screenshot")) }
                }
            },
            link: { hours in try await ShotLinks.upload(result(), hours: hours) },
            share: {
                guard let view = panel.contentView else { return }
                let at = view.convert(panel.mouseLocationOutsideOfEventStream, from: nil)
                NSSharingServicePicker(items: [Self.writeTempPNG(result())])
                    .show(relativeTo: NSRect(origin: at, size: .zero), of: view, preferredEdge: .maxY)
            },
            toSnippets: { [weak self] in self?.toSnippets(result()) }
        )
        let width = max(display.width + margin, ScreenshotView.minContentWidth) + 28
        panel = Self.makePanel(ScreenshotView(image: image, cgImage: cgImage, pixelSize: pixels, displaySize: display, actions: actions, doc: doc),
                          proposedWidth: width, resizable: true)
        panel.setFrameOrigin(Self.placed(panel.frame.size, centeredIn: visible))
        present(panel)
    }

    /// Text read off a screenshot, in a small window to select, fix and copy.
    func showText(_ text: String, title: LocalizedStringKey = "Text from Screenshot", sound: Bool = true) {
        if sound { Sound.shutter() }
        var panel: FloatingPanel!
        let view = TextResultView(text: text, title: title, copy: Self.copyText) { [weak self] in self?.close(panel) }
        panel = Self.makePanel(view, proposedWidth: 520, resizable: true)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        panel.setFrameOrigin(Self.placed(panel.frame.size, centeredIn: screen?.visibleFrame ?? .zero))
        present(panel)
    }

    /// A capture that didn't work (no permission…), said in the same window.
    func showProblem(_ error: Error) {
        let message: String = switch error {
        case AppError.permissionDenied:
            String(localized: "Shotleaf needs the Screen Recording permission. Allow it in System Settings → Privacy & Security, then restart Shotleaf.")
        default: error.localizedDescription
        }
        showText(message, title: "Couldn’t take the screenshot", sound: false)
    }

    static func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Sound.copied()
    }

    /// A small "3… 2… 1" badge near the top of the screen. It never reaches
    /// the shot: the picker leaves Shotleaf's own windows out.
    func countdown(_ seconds: Int) async {
        let model = Countdown(left: seconds)
        let panel = Self.makePanel(CountdownBadge(model: model))
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
        panel = Self.makePanel(PinnedScreenshotView(
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
    static func makePanel<V: View>(_ view: V, proposedWidth: CGFloat? = nil, resizable: Bool = false) -> FloatingPanel {
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

    /// `own`: the shot is in the clipboard history already, so it isn't recorded again.
    static func copy(_ png: Data, own: Bool = false) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        if own { pasteboard.setData(Data(), forType: ClipboardHistory.ownType) }
        Sound.copied()
    }

    /// The PNG in another format; PDF pages are sized in points (`scale` px per pt).
    static func encoded(_ png: Data, as type: UTType, scale: CGFloat) -> Data? {
        guard type != .png else { return png }
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let out = NSMutableData()
        if type == .pdf {
            var page = CGRect(x: 0, y: 0, width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
            guard let consumer = CGDataConsumer(data: out), let pdf = CGContext(consumer: consumer, mediaBox: &page, nil) else { return nil }
            pdf.beginPDFPage(nil)
            pdf.draw(image, in: page)
            pdf.endPDFPage()
            pdf.closePDF()
        } else {
            guard let destination = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
        }
        return out as Data
    }

    static let settings = SettingsStore()

    /// Settings → Screenshots, or the Desktop.
    static var saveFolder: URL {
        settings.saveFolder ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    /// Saves as "Shotleaf 2026-10-08 at 16.50.12.png" (the name and folder from
    /// Settings), at 1x if asked; `scale` = pixels per point of the shot.
    static func save(_ png: Data, to folder: URL? = nil, now: Date = Date(), scale: CGFloat = 1) -> URL? {
        let folder = folder ?? saveFolder
        let url = folder.appendingPathComponent(fileName(now, template: settings.fileNameTemplate))
        let data = settings.saveAt1x ? oneX(png, scale: scale) : png
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url)
            return url
        } catch {
            SaveError.show(error, saving: String(localized: "the screenshot"))
            return nil
        }
    }

    /// `template` with {date} and {time} filled in, made safe for Finder.
    static func fileName(_ date: Date, template: String = SettingsStore.defaultFileName) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let day = f.string(from: date)
        f.dateFormat = "HH.mm.ss"
        let name = template.replacingOccurrences(of: "{date}", with: day).replacingOccurrences(of: "{time}", with: f.string(from: date))
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return (name.isEmpty ? "\(AppInfo.name) \(day) at \(f.string(from: date))" : name) + ".png"
    }

    /// A Retina PNG scaled down to one pixel per point.
    static func oneX(_ png: Data, scale: CGFloat) -> Data {
        guard scale > 1, let image = NSBitmapImageRep(data: png)?.cgImage else { return png }
        let w = Int((CGFloat(image.width) / scale).rounded()), h = Int((CGFloat(image.height) / scale).rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return png }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage().flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) } ?? png
    }

    // MARK: Last shot & clipboard

    /// The newest captures, as taken (Application Support/Shotleaf/Recent).
    static var recentFolder: URL {
        AppInfo.supportFolder.appendingPathComponent("Recent", isDirectory: true)
    }
    static let recentLimit = 10

    /// Keeps a new capture (the oldest beyond `recentLimit` go). Survives a restart.
    @discardableResult
    static func remember(_ shot: ImagePayload, in folder: URL = recentFolder, now: Date = Date()) -> [URL] {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
        try? shot.data.write(to: folder.appendingPathComponent("\(f.string(from: now)).png"))
        let all = recent(in: folder, limit: .max)
        for old in all.dropFirst(recentLimit) { try? FileManager.default.removeItem(at: old) }
        return Array(all.prefix(recentLimit))
    }

    /// Newest first (the names sort by time).
    static func recent(in folder: URL = recentFolder, limit: Int = recentLimit) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return Array(files.filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent > $1.lastPathComponent }.prefix(limit))
    }

    static func load(_ url: URL) -> ImagePayload? {
        (try? Data(contentsOf: url)).flatMap(payload(fromImageData:))
    }

    /// The clipboard's image (PNG or anything AppKit reads), as a PNG payload.
    static func clipboardImage() -> ImagePayload? {
        let board = NSPasteboard.general
        guard let data = board.data(forType: .png) ?? board.data(forType: .tiff)
                ?? (NSImage(pasteboard: board)?.tiffRepresentation) else { return nil }
        return payload(fromImageData: data)
    }

    static func payload(fromImageData data: Data) -> ImagePayload? {
        guard let rep = NSBitmapImageRep(data: data), rep.pixelsWide > 0,
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return ImagePayload(data: png, width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    /// A drop target may read the file lazily, so it stays until the next launch
    /// clears `tempFolders`.
    private static func writeTempPNG(_ png: Data) -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Shotleaf Drag/\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName(Date()))
        try? png.write(to: url)
        return url
    }

    /// Where dragged, pasted and shared files wait for the app that takes them.
    static let tempFolders = ["Shotleaf Drag", "Shotleaf Paste", "Shotleaf Share"]

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
