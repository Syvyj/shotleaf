import AppKit
import EmbeddedKit
import ScreenCaptureKit

/// Developer run: `APILA --completion-live-test`. Types a sample sentence into
/// a scratch TextEdit document with real (unmarked) key events, the way a
/// person would, and reports what inline completion showed and when — with a
/// screenshot of the window before and after Tab. Needs APILA's own
/// Accessibility and Screen Recording permissions; nothing else.
@MainActor
public enum CompletionLiveTest {
    public static func run(_ coordinator: AppCoordinator, text: String, out: URL) async {
        let completion = coordinator.inlineCompletion
        // The test's emoji picks mustn't replace the user's recent emoji.
        let recents = UserDefaults.standard.object(forKey: "emojiRecents")
        defer { UserDefaults.standard.set(recents, forKey: "emojiRecents") }
        _ = try? await EmbeddedModel.completion.load() // measure typing, not the first load
        // "chrome:" — a web editor (contenteditable, like Claude's or Slack's
        // input) in a new Chrome tab; otherwise a scratch TextEdit document.
        var text = text
        let chrome = text.hasPrefix("chrome:")
        if chrome { text.removeFirst("chrome:".count) }
        let id = UUID().uuidString.prefix(6)
        let bundleID = chrome ? "com.google.Chrome" : "com.apple.TextEdit"
        let file: URL
        let documentName: String
        if chrome {
            documentName = "Shotleaf live test \(id)"
            file = FileManager.default.temporaryDirectory.appendingPathComponent("apila-live-test-\(id).html")
            let page = """
                <!doctype html><meta charset="utf-8"><title>\(documentName)</title>
                <div id="e" contenteditable="true" style="font: 16px -apple-system; margin: 40px; padding: 12px; border: 1px solid #ccc; min-height: 80px"></div>
                <script>document.getElementById('e').focus()</script>
                """
            try? page.write(to: file, atomically: true, encoding: .utf8)
        } else {
            file = FileManager.default.temporaryDirectory.appendingPathComponent("apila-live-test-\(id).txt")
            documentName = file.lastPathComponent
            try? Data().write(to: file)
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.open([file], withApplicationAt: appURL, configuration: configuration)
        try? await Task.sleep(for: .seconds(chrome ? 2.5 : 1.5))
        // Safety: every key below goes to whatever has focus. Type only while
        // the scratch document itself is focused — never into another app.
        let isScratchFocused = { (name: String) in Self.isScratchFocused(name, app: bundleID) }
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
        try? await Task.sleep(for: .milliseconds(500))
        guard isScratchFocused(documentName) else {
            let message = "aborted: the scratch document isn't focused — nothing was typed"
            try? message.write(to: out.appendingPathComponent("live-report.txt"), atomically: true, encoding: .utf8)
            print(message)
            return
        }

        // "#N" at the end: press digit N instead of Tab (the emoji picker).
        var acceptDigit: String?
        if let hash = text.lastIndex(of: "#"), text[text.index(after: hash)...].allSatisfy(\.isNumber), text.index(after: hash) < text.endIndex {
            acceptDigit = String(text[text.index(after: hash)...])
            text = String(text[..<hash])
        }
        // "|" marks where the cursor goes back to (mid-text): typed whole, then ← × the rest.
        let parts = text.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let full = parts.joined()
        var report = ["text: \(text)"]
        releaseCommand() // a ⌘ left "down" would turn every letter into a shortcut
        let started = ContinuousClock.now
        for character in full {
            guard isScratchFocused(documentName) else { return abort(out) }
            type(String(character))
            try? await Task.sleep(for: .milliseconds(70)) // a quick typist
        }
        if parts.count == 2 {
            for _ in parts[1] {
                guard isScratchFocused(documentName) else { return abort(out) }
                key(123) // ←
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
        let typedAt = ContinuousClock.now
        // Watch the suggestion appear after the last key.
        var firstSeen: Duration?
        for _ in 0..<40 {
            if completion.suggestion != nil || completion.pickerEmoji != nil, firstSeen == nil { firstSeen = ContinuousClock.now - typedAt }
            try? await Task.sleep(for: .milliseconds(25))
        }
        report.append("typing took \(typedAt - started)")
        report.append("suggestion after last key: \(firstSeen.map { "\($0)" } ?? "none") — \((completion.suggestion ?? "nil").debugDescription)")
        if let emoji = completion.pickerEmoji { report.append("emoji picker: \(emoji.joined(separator: " "))") }
        await snapshot(to: out.appendingPathComponent("live-before-tab.png"), app: bundleID)

        guard isScratchFocused(documentName) else { return abort(out) }
        if let acceptDigit { type(acceptDigit) } else { key(48) } // the digit / Tab
        try? await Task.sleep(for: .milliseconds(400))
        report.append("after accept: \((completion.suggestion ?? "nil").debugDescription)")
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        if let field = FocusedField.current(excluding: [], screenTop: top) {
            report.append("field now: \((field.beforeCursor + "‸" + field.afterCursor).debugDescription)")
        }
        await snapshot(to: out.appendingPathComponent("live-after-tab.png"), app: bundleID)

        // Close the scratch document (⌘W; TextEdit saves the temp file itself) —
        // only if it's still the one in front.
        if isScratchFocused(documentName) { commandW() }
        try? await Task.sleep(for: .milliseconds(300))
        try? report.joined(separator: "\n").write(to: out.appendingPathComponent("live-report.txt"), atomically: true, encoding: .utf8)
        print(report.joined(separator: "\n"))
    }

    /// `app` is the frontmost app and its focused window is our scratch file / tab.
    private static func isScratchFocused(_ documentName: String, app bundleID: String) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == bundleID else { return false }
        let app = AXUIElementCreateApplication(front.processIdentifier)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success, let window else { return false }
        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title)
        return (title as? String)?.hasPrefix(documentName.replacingOccurrences(of: ".txt", with: "")) == true
    }

    private static func abort(_ out: URL) {
        let message = "aborted mid-way: focus left the scratch document — stopped typing"
        try? message.write(to: out.appendingPathComponent("live-report.txt"), atomically: true, encoding: .utf8)
        print(message)
    }

    private static func type(_ s: String) {
        let units = Array(s.utf16)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
            event?.flags = [] // plain letters, whatever the modifier state
            event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func key(_ code: CGKeyCode) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
    }

    /// ⌘W as a person presses it: ⌘ down, W, ⌘ up — so ⌘ never stays "held".
    private static func commandW() {
        CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: true).map { $0.flags = .maskCommand; $0.post(tap: .cghidEventTap) }
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 13, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
        releaseCommand()
    }

    private static func releaseCommand() {
        CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: false).map { $0.flags = []; $0.post(tap: .cghidEventTap) }
    }

    private static func snapshot(to url: URL, app bundleID: String) async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { $0.owningApplication?.bundleIdentifier == bundleID && $0.windowLayer == 0 }),
              let display = content.displays.first(where: { $0.frame.intersects(window.frame) })
        else { return }
        // The window plus a margin, from the whole display, so APILA's ghost text is in it too.
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = window.frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY).insetBy(dx: -20, dy: -20)
        config.width = Int(config.sourceRect.width * 2)
        config.height = Int(config.sourceRect.height * 2)
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url)
    }
}
