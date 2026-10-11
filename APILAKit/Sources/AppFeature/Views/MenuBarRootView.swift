import SwiftUI
import AppKit

/// The menu bar menu: screenshots, text from a screenshot, settings, quit.
public struct MenuBarRootView: View {
    @Bindable private var coordinator: AppCoordinator

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        Button(Self.label(String(localized: "Screenshot…"), coordinator.actionHotkeys[.capture])) {
            coordinator.takeScreenshot()
        }
        Button(Self.label(String(localized: "Scrolling Screenshot…"), coordinator.actionHotkeys[.scrolling])) {
            coordinator.takeScrollingScreenshot()
        }
        Menu("Screenshot with Delay") {
            Button("In 3 Seconds") { coordinator.takeScreenshot(delay: 3) }
            Button("In 5 Seconds") { coordinator.takeScreenshot(delay: 5) }
            Button("In 10 Seconds") { coordinator.takeScreenshot(delay: 10) }
        }
        Button(Self.label(String(localized: "Text from Screenshot…"), coordinator.actionHotkeys[.screenshotText])) {
            coordinator.textFromScreenshot()
        }
        Button(Self.label(String(localized: "Edit Last Screenshot"), coordinator.actionHotkeys[.editLast])) {
            coordinator.editLastScreenshot()
        }
        Button(Self.label(String(localized: "Edit Image from Clipboard"), coordinator.actionHotkeys[.editClipboard])) {
            coordinator.editClipboardImage()
        }
        Button("Watermark Photos…") { coordinator.showBatchWatermark() }
        Menu("Recent Screenshots") {
            ForEach(coordinator.recentShots, id: \.self) { url in
                Button {
                    coordinator.openRecent(url)
                } label: {
                    if let thumb = Self.thumbnail(url) { Image(nsImage: thumb) }
                    Text(Self.recentTitle(url))
                }
            }
            if coordinator.recentShots.isEmpty { Text("No screenshots yet") }
            Divider()
            Button("Show in Finder") { coordinator.showRecentFolder() }
        }

        Divider()

        Menu("Clipboard History") {
            Button(Self.label(String(localized: "Open Clipboard…"), coordinator.actionHotkeys[.clipboard])) { coordinator.showClipboard() }
            Button(Self.label(String(localized: "Snippets…"), coordinator.actionHotkeys[.snippets])) { coordinator.showClipboard(snippets: true) }
            Button("Edit Snippets…") { coordinator.showSnippetEditor() }
            Divider()
            ForEach(Array(coordinator.clipboard.items.prefix(10).enumerated()), id: \.element.id) { i, item in
                Button("\(i + 1). \(String(ClipboardPanelView.line(item).prefix(50)))") { coordinator.pasteFromHistory(item.id) }
            }
            if coordinator.clipboard.items.isEmpty { Text("Nothing copied yet") }
            Divider()
            if coordinator.clipboard.isPaused {
                Button("Resume Recording") { coordinator.pauseClipboard(minutes: nil) }
            } else {
                Button("Pause for 5 Minutes") { coordinator.pauseClipboard(minutes: 5) }
            }
            Button("Clear History") { coordinator.clipboard.clear() }
        }

        Toggle("Complete my text as I type", isOn: Binding(
            get: { coordinator.completionEnabled }, set: { coordinator.setCompletion($0) }
        ))
        SettingsLink { Text("Settings…") }
        Button("Setup Guide…") { coordinator.showOnboarding() }

        Divider()

        Button("Quit APILA") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// "14:05" today, "11 Oct 2026, 14:05" before, from the file's time-stamped name.
    static func recentTitle(_ url: URL) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
        guard let date = f.date(from: url.deletingPathExtension().lastPathComponent) else { return url.lastPathComponent }
        return date.formatted(date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated, time: .shortened)
    }

    /// A small picture for the menu row.
    /// ponytail: decodes up to 10 full PNGs each time the menu opens; cache if it ever feels slow.
    static func thumbnail(_ url: URL) -> NSImage? {
        guard let image = NSImage(contentsOf: url), image.size.width > 0 else { return nil }
        let side: CGFloat = 32
        let size = image.size.width >= image.size.height
            ? CGSize(width: side, height: max(1, side * image.size.height / image.size.width))
            : CGSize(width: max(1, side * image.size.width / image.size.height), height: side)
        let thumb = NSImage(size: size, flipped: false) { rect in image.draw(in: rect); return true }
        return thumb
    }

    private static func label(_ title: String, _ shortcut: HotkeyShortcut?) -> String {
        shortcut.map { "\(title) (\($0.title))" } ?? title
    }
}
