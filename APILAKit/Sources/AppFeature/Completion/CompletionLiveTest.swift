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
        _ = try? await EmbeddedModel.completion.load() // measure typing, not the first load
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("apila-live-test-\(UUID().uuidString.prefix(6)).txt")
        try? Data().write(to: file)
        guard let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.open([file], withApplicationAt: textEdit, configuration: configuration)
        try? await Task.sleep(for: .seconds(1.5))

        var report = ["text: \(text)"]
        let started = ContinuousClock.now
        for character in text {
            type(String(character))
            try? await Task.sleep(for: .milliseconds(70)) // a quick typist
        }
        let typedAt = ContinuousClock.now
        // Watch the suggestion appear after the last key.
        var firstSeen: Duration?
        for _ in 0..<40 {
            if completion.suggestion != nil, firstSeen == nil { firstSeen = ContinuousClock.now - typedAt }
            try? await Task.sleep(for: .milliseconds(25))
        }
        report.append("typing took \(typedAt - started)")
        report.append("suggestion after last key: \(firstSeen.map { "\($0)" } ?? "none") — \((completion.suggestion ?? "nil").debugDescription)")
        await snapshot(to: out.appendingPathComponent("live-before-tab.png"))

        key(48) // Tab
        try? await Task.sleep(for: .milliseconds(400))
        report.append("after Tab: \((completion.suggestion ?? "nil").debugDescription)")
        await snapshot(to: out.appendingPathComponent("live-after-tab.png"))

        // Close the scratch document (⌘W; TextEdit saves the temp file itself).
        key(13, flags: .maskCommand)
        try? await Task.sleep(for: .milliseconds(300))
        try? report.joined(separator: "\n").write(to: out.appendingPathComponent("live-report.txt"), atomically: true, encoding: .utf8)
        print(report.joined(separator: "\n"))
    }

    private static func type(_ s: String) {
        let units = Array(s.utf16)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
            event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func snapshot(to url: URL) async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { $0.owningApplication?.bundleIdentifier == "com.apple.TextEdit" && $0.windowLayer == 0 }),
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
