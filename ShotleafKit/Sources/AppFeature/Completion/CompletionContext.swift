import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision

/// What inline completion knows besides the text before the cursor: the app
/// and window, the text on screen (the chat, the page — read with on-device
/// OCR), and something just copied. Screen text is refreshed in the
/// background every few seconds, never per keystroke; the clipboard is read
/// only when it changes (reading it each time would make macOS ask).
@MainActor
final class CompletionContext {
    var useScreen = true
    var useClipboard = true

    private struct ScreenCache {
        let pid: pid_t
        let window: String
        let text: String
        let at: Date
    }
    private var screen: ScreenCache?
    private var reading = false
    private static let screenMaxAge: TimeInterval = 8 // OCR shares the GPU with the model

    private var clipboardChange = NSPasteboard.general.changeCount
    private var clipboard: (text: String, at: Date)?
    private static let clipboardMaxAge: TimeInterval = 5 * 60

    /// The context for a request now. Kicks off a screen refresh when the
    /// cached text is old or belongs to another window — that one is used
    /// from the next request on.
    func current(for field: FocusedField) -> CompletionText.Context {
        let pid = field.pid, window = field.windowTitle
        var context = CompletionText.Context(app: field.appName, window: window)

        if useScreen {
            if let screen, screen.pid == pid, screen.window == window { context.screen = screen.text }
            if screen == nil || screen?.pid != pid || screen?.window != window
                || Date().timeIntervalSince(screen?.at ?? .distantPast) > Self.screenMaxAge {
                refreshScreen(pid: pid, window: window)
            }
        }
        if useClipboard {
            let pasteboard = NSPasteboard.general
            if pasteboard.changeCount != clipboardChange {
                clipboardChange = pasteboard.changeCount
                // Never a password or a token: the model could offer it back as a suggestion.
                clipboard = pasteboard.string(forType: .string).flatMap { ClipboardHistory.isPrivate(pasteboard, text: $0) ? nil : ($0, Date()) }
            }
            if let clipboard, Date().timeIntervalSince(clipboard.at) < Self.clipboardMaxAge {
                context.clipboard = clipboard.text
            }
        }
        return context
    }

    /// Screen-records the app's front window and reads its text.
    private func refreshScreen(pid: pid_t, window: String) {
        guard !reading, CGPreflightScreenCaptureAccess() else { return }
        reading = true
        Task {
            defer { reading = false }
            guard let image = await Self.captureFrontWindow(of: pid) else { return }
            let text = await Self.recognize(image)
            screen = ScreenCache(pid: pid, window: window, text: text, at: Date())
        }
    }

    private static func captureFrontWindow(of pid: pid_t) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              // Front to back: the first normal window of the app is the one being typed in.
              let window = content.windows.first(where: {
                  $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 80 && $0.frame.height > 60
              })
        else { return nil }
        let config = SCStreamConfiguration()
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        return try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
    }

    /// On-device OCR, top to bottom (Ukrainian and English).
    private nonisolated static func recognize(_ image: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["uk-UA", "en-US"]
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                continuation.resume(returning: "")
            }
        }
    }
}
