#if DEBUG
import AppKit
import ScreenCaptureKit
import SwiftUI

/// Developer run (`--guide-shots <folder>`): Shotleaf's real windows, filled with
/// made-up data, saved as PNGs for the guide on the site. Nothing of the user's
/// shows: the history and snippets live in a temp folder, and the settings that
/// could name a person or a server are overridden for this run only. A plain
/// backdrop covers the screen meanwhile, so the glass shows no desktop through it.
/// Run once per language: `open -n Shotleaf.app --args --guide-shots DIR -AppleLanguages "(uk)"`.
@MainActor
public enum GuideShots {
    public static func run(_ coordinator: AppCoordinator, out: URL) async {
        NSApp.appearance = NSAppearance(named: .aqua)
        let uk = Bundle.main.preferredLocalizations.first == "uk"
        let lang = uk ? "uk" : "en"
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("Shotleaf Guide \(UUID())", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        override([:])

        let backdrop = Self.backdrop()
        defer { backdrop.orderOut(nil) }
        // The pointer out of the way (no hover tips in the shots), back where it was at the end.
        let pointer = NSEvent.mouseLocation, height = NSScreen.screens.first?.frame.height ?? 0
        CGWarpMouseCursorPosition(CGPoint(x: 2, y: height / 2))
        defer { CGWarpMouseCursorPosition(CGPoint(x: pointer.x, y: height - pointer.y)) }
        NSApp.activate(ignoringOtherApps: true) // Settings and the setup guide drawn as the active window
        let demo = Demo(uk: uk)
        let shot = demo.screenshot()

        // The editor, marked up.
        await snap(editor(shot, marks: true, callout: uk ? "Нова дата!" : "New date!"), "editor", lang, out)
        await snap(editor(shot, marks: false, framed: true, watermark: uk ? "© Студія" : "© Studio"), "editor-background", lang, out)
        // Pinned on top.
        await snap(ScreenshotWindows.makePanel(PinnedScreenshotView(image: NSImage(cgImage: shot, size: .zero),
                                                                    size: CGSize(width: 520, height: 325), copy: {}, close: {})), "pinned", lang, out)
        // Text from a screenshot.
        await snap(ScreenshotWindows.makePanel(TextResultView(text: demo.recognized, title: "Text from Screenshot", copy: { _ in }, close: {}),
                                               proposedWidth: 520), "text", lang, out)

        // The clipboard and snippets, from demo stores.
        let history = ClipboardHistory(folder: temp.appendingPathComponent("Clipboard"))
        demo.fill(history, screenshot: shot)
        let snippets = SnippetStore(file: temp.appendingPathComponent("snippets.json"))
        demo.fill(snippets)
        let panel: (ClipboardPanelModel) -> FloatingPanel = { model in
            ScreenshotWindows.makePanel(ClipboardPanelView(model: model, pick: { _, _ in }, close: {}))
        }
        // The panel focuses its search field as it opens, which resets the selection: set it after.
        var model = ClipboardPanelModel(history: history, snippets: snippets)
        await snap(panel(model), "clipboard", lang, out)
        model = ClipboardPanelModel(history: history, snippets: snippets)
        await snap(panel(model), "clipboard-search", lang, out) { model.query = "imax" }
        model = ClipboardPanelModel(history: history, snippets: snippets)
        await snap(panel(model), "clipboard-actions", lang, out) { model.selected = 1; model.actionsShown = true } // the link
        model = ClipboardPanelModel(history: history, snippets: snippets)
        model.showsSnippets = true
        await snap(panel(model), "snippets", lang, out)
        model = ClipboardPanelModel(history: history, snippets: snippets)
        model.showsSnippets = true
        await snap(panel(model), "snippets-question", lang, out) { model.asking = snippets.snippets.first }

        let editor = ScreenshotWindows.makePanel(SnippetEditorView(store: snippets), proposedWidth: 1000, resizable: true)
        editor.setContentSize(NSSize(width: 1000, height: max(editor.frame.height, 680)))
        await snap(editor, "snippet-editor", lang, out)

        // Watermarking a folder of photos.
        let batch = BatchWatermark()
        batch.add(demo.photos(in: temp))
        batch.outputFolder = URL(fileURLWithPath: "/Users/Shared/Watermarked", isDirectory: true)
        batch.watermark = Watermark(text: uk ? "© Студія" : "© Studio", position: 8, size: 0.24, opacity: 0.7)
        let batchWindow = ScreenshotWindows.makePanel(BatchWatermarkView(model: batch, close: {}), proposedWidth: 1100, resizable: true)
        batchWindow.setContentSize(NSSize(width: 1100, height: max(batchWindow.frame.height, 700)))
        await snap(batchWindow, "watermark-photos", lang, out)

        // The setup guide and Settings, as they are on this Mac (permissions on).
        coordinator.showOnboarding()
        try? await Task.sleep(for: .milliseconds(400))
        if let setup = NSApp.windows.first(where: { $0.title == String(localized: "Welcome to Shotleaf") }) { await snap(setup, "setup", lang, out) }
        coordinator.closeOnboarding()
        // The real Settings window; the pane it opens on is the user's choice, put back after.
        let lastPane = UserDefaults.standard.string(forKey: "settingsPane")
        let opener = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: .borderless, backing: .buffered, defer: false)
        opener.contentView = NSHostingView(rootView: SettingsOpener())
        opener.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(800))
        opener.orderOut(nil)
        if let settings = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("Settings") == true }) {
            for pane in SettingsRootView.Pane.allCases {
                await snap(settings, "settings-\(pane.rawValue)", lang, out, keep: true) { UserDefaults.standard.set(pane.rawValue, forKey: "settingsPane") }
            }
            settings.close()
        }
        UserDefaults.standard.set(lastPane, forKey: "settingsPane")
    }

    // MARK: Windows

    private static func editor(_ shot: CGImage, marks: Bool, callout: String = "", framed: Bool = false, watermark: String? = nil) -> FloatingPanel {
        let doc = AnnotationDocument()
        let size = CGSize(width: shot.width / 2, height: shot.height / 2)
        if marks {
            doc.color = .coral
            doc.add(.rectangle(CGRect(x: 28, y: 80, width: 300, height: 58)))
            doc.add(.arrow(from: CGPoint(x: 520, y: 70), to: CGPoint(x: 342, y: 106)))
            doc.add(.step(center: CGPoint(x: 28, y: 80), number: 1))
            doc.add(.text(origin: CGPoint(x: 420, y: 24), string: callout, tail: nil))
            doc.add(.blur(CGRect(x: 32, y: 210, width: 200, height: 34)))
            doc.tool = .arrow
            doc.selection = nil
        }
        if framed { doc.backdrop = Backdrop() }
        if let watermark { doc.watermark = Watermark(text: watermark, position: 8, size: 0.2, opacity: 0.6) }
        let actions = ScreenshotActions(copy: {}, save: { nil }, pin: {}, close: {}, dragFile: { nil })
        let width = max(size.width + 2 * ScreenshotView.margin, ScreenshotView.minContentWidth) + 28
        return ScreenshotWindows.makePanel(ScreenshotView(image: NSImage(cgImage: shot, size: size), cgImage: shot,
                                                          pixelSize: CGSize(width: shot.width, height: shot.height), displaySize: size,
                                                          actions: actions, doc: doc),
                                           proposedWidth: width, resizable: true)
    }

    /// A plain sheet over the whole screen, under the windows being shot.
    private static func backdrop() -> NSWindow {
        let frame = NSScreen.main?.frame ?? .zero
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = NSColor(srgbRed: 0.953, green: 0.957, blue: 0.933, alpha: 1) // the site's paper
        window.level = .normal
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        return window
    }

    /// Settings read for this run only (the argument domain beats the saved ones).
    private static func override(_ extra: [String: Any]) {
        let fixed: [String: Any] = ["saveFolder": "", ShotLinks.serverKey: "", "snippetFolder": "", "watermark": Data()]
        UserDefaults.standard.setVolatileDomain(fixed.merging(extra) { $1 }, forName: UserDefaults.argumentDomain)
    }

    // MARK: Capture

    /// `then`: state to set once the window is up (views may reset it as they appear).
    private static func snap(_ window: NSWindow, _ name: String, _ lang: String, _ out: URL, keep: Bool = false, then: () -> Void = {}) async {
        let visible = NSScreen.main?.visibleFrame ?? .zero
        window.setFrameOrigin(NSPoint(x: visible.midX - window.frame.width / 2, y: visible.midY - window.frame.height / 2))
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(300))
        then()
        try? await Task.sleep(for: .milliseconds(900)) // layout, thumbnails, the glass
        do {
            let image = try await capture(window)
            let rep = NSBitmapImageRep(cgImage: image)
            try rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("\(name)-\(lang).png"))
            print("guide shot:", name, lang, image.width, "×", image.height)
        } catch {
            print("guide shot failed:", name, error)
        }
        if !keep { window.orderOut(nil) }
    }

    private static func capture(_ window: NSWindow) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let found = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let filter = SCContentFilter(desktopIndependentWindow: found)
        let config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

/// Opens the real Settings window, the way the menu does.
private struct SettingsOpener: View {
    @Environment(\.openSettings) private var openSettings
    var body: some View { Color.clear.onAppear { openSettings() } }
}

/// The made-up content: a page to screenshot, a clipboard history, snippets, photos.
@MainActor
private struct Demo {
    let uk: Bool

    var recognized: String {
        uk ? "Зустріч з командою — четвер, 14:00\nПорядок денний: звіт за Q3, бюджет на осінь\nПереговорна «Липа», 3 поверх"
           : "Team meeting — Thursday, 2 pm\nAgenda: Q3 report, autumn budget\nRoom “Linden”, 3rd floor"
    }

    /// A small page to take a screenshot of, drawn here (not anyone's real screen).
    func screenshot() -> CGImage {
        let renderer = ImageRenderer(content: DemoPage(uk: uk))
        renderer.scale = 2
        return renderer.cgImage!
    }

    func fill(_ history: ClipboardHistory, screenshot: CGImage) {
        let now = Date()
        func item(_ kind: ClipItem.Kind, _ text: String, app: String, id: String, minutes: Double) -> ClipItem {
            var item = ClipItem(kind: kind, text: text)
            item.appName = app
            item.bundleID = id
            item.date = now.addingTimeInterval(-minutes * 60)
            return item
        }
        let png = NSBitmapImageRep(cgImage: screenshot).representation(using: .png, properties: [:])
        var shot = item(.image, "", app: "Shotleaf", id: "dev.syvyj.shotleaf", minutes: 300)
        shot.hasImage = true
        shot.screenshot = true
        shot.imageSize = CGSize(width: screenshot.width, height: screenshot.height)
        let items = [
            (shot, png),
            (item(.text, uk ? "Київ, вул. Хрещатик, 22, офіс 5" : "22 Linden Street, office 5", app: "Notes", id: "com.apple.Notes", minutes: 240), nil),
            (item(.file, "/Users/Shared/" + (uk ? "рахунок-0142.pdf" : "invoice-0142.pdf"), app: "Finder", id: "com.apple.finder", minutes: 180), nil),
            (item(.text, uk ? "Нотатки з дзвінка — план на Q3" : "Notes from the call — Q3 plan", app: "Notes", id: "com.apple.Notes", minutes: 60), nil),
            (item(.color, "#7CB342", app: "Digital Color Meter", id: "com.apple.DigitalColorMeter", minutes: 9), nil),
            (item(.link, "https://shop.example/item?id=7&utm_source=newsletter&utm_campaign=autumn", app: "Safari", id: "com.apple.Safari", minutes: 2), nil),
            (item(.text, uk ? "IMAX у неділю — 2 місця, ряд G" : "IMAX on Sunday — 2 seats, row G", app: "Messages", id: "com.apple.MobileSMS", minutes: 0), nil),
        ]
        for (clip, png) in items { history.add(clip, png: png) } // oldest first: the newest ends on top
    }

    func fill(_ store: SnippetStore) {
        let work = SnippetFolder(name: uk ? "Робота" : "Work", color: 0)
        let home = SnippetFolder(name: uk ? "Особисте" : "Personal", color: 1)
        store.folders = [work, home]
        store.snippets = [
            Snippet(title: uk ? "Відповідь клієнту" : "Reply to a client",
                    text: uk ? "Добрий день, {?Ім’я}!\nДякую за звернення, надішлю рахунок до {date}.\n{cursor}\n\nЗ повагою,\nОксана"
                             : "Hello {?Name},\nThanks for reaching out — I’ll send the invoice by {date}.\n{cursor}\n\nBest,\nOksana",
                    abbreviation: uk ? ";відп" : ";reply", folder: work.id),
            Snippet(title: uk ? "Реквізити" : "Bank details",
                    text: uk ? "ФОП Петренко О. В.\nIBAN UA00 1234 5678 0000 0000 0000 001" : "Oksana Petrenko\nIBAN UA00 1234 5678 0000 0000 0000 001",
                    abbreviation: ";iban", folder: work.id),
            Snippet(title: uk ? "Підпис" : "Signature", text: uk ? "Оксана Петренко · студія «Липа»" : "Oksana Petrenko · Linden Studio",
                    abbreviation: ";sig", folder: work.id),
            Snippet(title: uk ? "Адреса доставки" : "Delivery address", text: uk ? "Київ, вул. Хрещатик, 22, офіс 5" : "22 Linden Street, office 5",
                    abbreviation: ";addr", folder: home.id),
            Snippet(title: uk ? "Сьогоднішня дата" : "Today’s date", text: "{date}", abbreviation: ";today", folder: home.id),
        ]
    }

    /// Six "photos": soft colour fields, made here.
    func photos(in folder: URL) -> [URL] {
        let pairs: [(Color, Color)] = [(.orange, .red), (.cyan, .blue), (.green, .teal), (.pink, .purple), (.yellow, .brown), (.mint, .indigo)]
        return pairs.enumerated().compactMap { i, pair in
            let renderer = ImageRenderer(content: LinearGradient(colors: [pair.0.opacity(0.85), pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: 1200, height: 900))
            guard let image = renderer.cgImage,
                  let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
            let url = folder.appendingPathComponent("photo-\(i + 1).jpg")
            try? jpeg.write(to: url)
            return url
        }
    }
}

/// What the demo screenshot shows: a calendar card, in the app's own palette.
private struct DemoPage: View {
    let uk: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(uk ? "Зустріч з командою" : "Team meeting").font(.system(size: 30, weight: .bold))
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                Text(uk ? "Четвер, 14:00 — 15:00" : "Thursday, 2 — 3 pm")
            }
            .font(.system(size: 20, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color(red: 0.86, green: 0.92, blue: 0.77), in: RoundedRectangle(cornerRadius: 10))
            Text(uk ? "Порядок денний: звіт за Q3, бюджет на осінь." : "Agenda: Q3 report, autumn budget.")
                .font(.system(size: 18)).foregroundStyle(.secondary)
            Text(uk ? "Переговорна «Липа», 3 поверх" : "Room “Linden”, 3rd floor").font(.system(size: 18))
            Text(uk ? "Код дверей: 4821" : "Door code: 4821").font(.system(size: 18, weight: .medium))
            Spacer(minLength: 0)
        }
        .padding(36)
        .frame(width: 640, height: 400, alignment: .topLeading)
        .background(.white)
    }
}
#endif
