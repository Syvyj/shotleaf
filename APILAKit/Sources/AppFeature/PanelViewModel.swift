import Core
import ActionKit
import AppKit
import Observation

/// State machine for the Floating Panel: actions → (prompt) → generating →
/// result. Holds the snapshot captured at hotkey time and runs actions against
/// it (no re-gathering). UI flow only; business logic stays in the Kits.
@MainActor
@Observable
public final class PanelViewModel {
    public enum Screen: Equatable { case actions, customPrompt, generating, result }

    /// What the prompt field is for.
    public enum PromptMode: Equatable {
        case custom      // instruction applied to the selection
        case refine      // instruction applied to the current result
        case screenshot  // question about a just-captured screenshot
    }

    public enum Item: Identifiable {
        case action(any Action)
        case customPrompt
        case screenshotText
        case screenshotAsk

        public var id: String {
            switch self {
            case .action(let a): a.id
            case .customPrompt: "custom"
            case .screenshotText: "screenshot-text"
            case .screenshotAsk: "screenshot-ask"
            }
        }
        public var title: String {
            switch self {
            case .action(let a): a.title
            case .customPrompt: String(localized: "Custom Prompt")
            case .screenshotText: String(localized: "Text from Screenshot…")
            case .screenshotAsk: String(localized: "Ask about Screenshot…")
            }
        }
    }

    public private(set) var screen: Screen = .actions
    public private(set) var promptMode: PromptMode = .custom
    public var isRefining: Bool { screen == .customPrompt && promptMode == .refine }
    public var selectedIndex = 0
    public var customPromptText = ""
    public private(set) var output = ""
    public private(set) var errorText: String?
    public private(set) var noticeText: String?
    public private(set) var items: [Item] = []
    /// The current provider is the canned Mock (no real model reachable).
    public var isMockProvider = false
    /// e.g. "LM Studio · local-model" — shown in the panel header.
    public var providerName = ""

    private let runner: ActionRunner
    private let inserter: ResultInserter
    private let accessibilityGranted: () -> Bool
    private let captureScreen: () async throws -> ImagePayload
    private var snapshot: ContextSnapshot?
    /// The selection snapshot + the captured image, while asking about it.
    private var screenshotSnapshot: ContextSnapshot?
    private var sourceApp: NSRunningApplication?
    private var streamTask: Task<Void, Never>?
    private var lastRun: (action: any Action, snapshot: ContextSnapshot)?

    public var onClose: () -> Void = {}
    /// The panel must get out of the way while the user picks a screen region.
    public var onHide: () -> Void = {}
    public var onShow: () -> Void = {}
    /// Called with each successful result (for History).
    public var onResult: (_ title: String, _ output: String) -> Void = { _, _ in }

    public init(
        runner: ActionRunner,
        inserter: ResultInserter,
        actions: [any Action],
        accessibilityGranted: @escaping () -> Bool,
        captureScreen: @escaping () async throws -> ImagePayload = { throw AppError.notImplemented("screen capture") }
    ) {
        self.runner = runner
        self.inserter = inserter
        self.accessibilityGranted = accessibilityGranted
        self.captureScreen = captureScreen
        setActions(actions)
    }

    public func setActions(_ actions: [any Action]) {
        items = actions.map { .action($0) } + [.customPrompt, .screenshotText, .screenshotAsk]
        selectedIndex = min(selectedIndex, items.count - 1)
    }

    /// What the actions will run on, so the user sees it before anything is sent:
    /// the selection, or — when nothing is selected — the clipboard.
    public var contextPreview: (source: String, text: String)? {
        if let text = snapshot?.selectedText, !text.isEmpty { return (String(localized: "Selection"), Self.preview(text)) }
        if let text = snapshot?.clipboardText, !text.isEmpty { return (String(localized: "Clipboard"), Self.preview(text)) }
        return nil
    }

    private static func preview(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return flat.count > 90 ? String(flat.prefix(90)) + "…" : flat
    }

    public func present(snapshot: ContextSnapshot, sourceApp: NSRunningApplication?) {
        streamTask?.cancel()
        self.snapshot = snapshot
        self.sourceApp = sourceApp
        screen = .actions
        promptMode = .custom
        selectedIndex = 0
        output = ""
        errorText = nil
        noticeText = nil
        customPromptText = ""
        screenshotSnapshot = nil
        lastRun = nil
    }

    public func moveUp() { if screen == .actions { selectedIndex = max(0, selectedIndex - 1) } }
    public func moveDown() { if screen == .actions { selectedIndex = min(items.count - 1, selectedIndex + 1) } }

    public func confirm() {
        switch screen {
        case .actions:
            switch items[selectedIndex] {
            case .action(let action): if let snapshot { run(action, on: snapshot) }
            case .customPrompt: openPrompt(.custom)
            case .screenshotText: startScreenshot(ask: false)
            case .screenshotAsk: startScreenshot(ask: true)
            }
        case .customPrompt:
            let text = customPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let snapshot else { return }
            switch promptMode {
            case .custom:
                run(CustomPromptAction(prompt: text), on: snapshot)
            case .refine:
                // Refining works on the previous result instead of the original selection.
                run(CustomPromptAction(prompt: text), on: ContextSnapshot(selectedText: output, capturedAt: Date()))
            case .screenshot:
                if let shot = screenshotSnapshot { run(AskAboutScreenshotAction(prompt: text), on: shot) }
            }
        case .generating:
            break
        case .result:
            Task { await copyResult() }
        }
    }

    /// Capture a region, then OCR it (`ask == false`) or ask a question about it.
    /// `reopenOnCancel`: after Esc, bring the action list back (panel flow) or
    /// stay hidden (started from the menu, there was no panel).
    public func startScreenshot(ask: Bool, reopenOnCancel: Bool = true) {
        Task {
            guard let shot = await captureRegion(reopenOnCancel: reopenOnCancel) else { return }
            use(shot, ask: ask)
        }
    }

    /// An already-captured image (e.g. from the screenshot window): OCR it or ask about it.
    public func useScreenshot(_ image: ImagePayload, ask: Bool) {
        guard let snapshot else { return }
        use(snapshot.withScreenImage(image), ask: ask)
    }

    private func use(_ shot: ContextSnapshot, ask: Bool) {
        if ask {
            screenshotSnapshot = shot
            openPrompt(.screenshot)
        } else {
            run(ScreenshotTextAction(), on: shot)
        }
    }

    /// Shows an error on the result screen (e.g. a failed capture outside the panel).
    public func showError(_ error: Error) {
        errorText = Self.friendlyMessage(for: error)
        output = ""
        screen = .result
    }

    private func openPrompt(_ mode: PromptMode) {
        customPromptText = ""
        promptMode = mode
        screen = .customPrompt
    }

    /// Hides the panel, lets the user pick a region, brings the panel back.
    /// Nil if they pressed Esc or it failed (then the error is shown).
    private func captureRegion(reopenOnCancel: Bool) async -> ContextSnapshot? {
        guard let snapshot else { return nil }
        onHide()
        do {
            let shot = snapshot.withScreenImage(try await captureScreen())
            onShow()
            return shot
        } catch AppError.cancelled {
            if reopenOnCancel { onShow() }
            return nil
        } catch {
            errorText = Self.friendlyMessage(for: error)
            screen = .result
            onShow()
            return nil
        }
    }

    /// Runs the last action again (same input) — for a different take.
    public func retry() {
        guard screen == .result, let lastRun else { return }
        run(lastRun.action, on: lastRun.snapshot)
    }

    /// Opens the prompt field to adjust the result ("shorter", "more formal"…).
    public func refine() {
        guard screen == .result, errorText == nil, !output.isEmpty else { return }
        openPrompt(.refine)
    }

    private func run(_ action: any Action, on snapshot: ContextSnapshot) {
        lastRun = (action, snapshot)
        screen = .generating
        output = ""
        errorText = nil
        noticeText = nil
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await out in self.runner.run(action, snapshot: snapshot) {
                    switch out {
                    case .token(let chunk): self.output += chunk.text
                    case .text(let text): self.output += text
                    default: break
                    }
                }
            } catch {
                // Closed mid-generation: the panel is already gone, don't flip it to an error.
                if Task.isCancelled { return }
                self.errorText = Self.friendlyMessage(for: error)
            }
            if Task.isCancelled { return }
            self.screen = .result
            if self.errorText == nil, !self.output.isEmpty {
                self.onResult(action.title, self.output)
            }
        }
    }

    static func friendlyMessage(for error: Error) -> String {
        if let error = error as? AppError {
            switch error {
            case .missingContext(let what) where what.contains("screenshot"):
                return "\(what)."
            case .missingContext:
                return String(localized: "No text found. Select some text (or copy it), then open APILA again.")
            case .providerUnavailable:
                return String(localized: "No AI provider is available. Start LM Studio (or an OpenAI-compatible server), or rely on Mock.")
            case .permissionDenied(let name):
                return String(localized: "APILA needs the \(name) permission. Allow it in System Settings → Privacy & Security, then restart APILA.")
            case .cancelled:
                return String(localized: "Cancelled.")
            case .notImplemented(let what):
                return String(localized: "Not available yet: \(what).")
            }
        }
        guard let error = error as? InferenceError else { return error.localizedDescription }
        switch error {
        case .network, .timedOut, .unhealthy, .invalidURL:
            return String(localized: "Can't reach the model server. Is LM Studio running with a model loaded?")
        case .noModelSelected:
            return String(localized: "No model selected. Load a model in LM Studio.")
        case .api(let message, _, _):
            return String(localized: "Model server error: \(message)")
        case .http(let status, let body):
            return String(localized: "Model server error (HTTP \(status)): \(body ?? "")")
        case .decoding:
            return String(localized: "Unexpected response from the model server.")
        case .cancelled:
            return String(localized: "Cancelled.")
        }
    }

    public func copyResult() async {
        await inserter.copy(output)
        close()
    }

    public func replaceSelection() async { await paste(insertBelow: false) }
    public func insertBelow() async { await paste(insertBelow: true) }

    /// Synthetic ⌘V needs Accessibility. If it's off, we still copy the result
    /// and tell the user — instead of silently "doing nothing".
    private func paste(insertBelow: Bool) async {
        let app = sourceApp
        let text = output
        guard accessibilityGranted() else {
            await inserter.copy(text)
            noticeText = String(localized: "Accessibility is off — result copied to clipboard. Paste with ⌘V, or enable Accessibility in Settings to auto-paste.")
            return
        }
        close()
        if insertBelow {
            await inserter.insertBelow(text, in: app)
        } else {
            await inserter.replaceSelection(text, in: app)
        }
    }

    /// Esc: leaves Refine back to the result; otherwise closes the panel.
    public func cancel() {
        if isRefining {
            promptMode = .custom
            screen = .result
        } else {
            close()
        }
    }

    public func close() {
        streamTask?.cancel()
        screen = .actions
        promptMode = .custom
        onClose()
    }
}
