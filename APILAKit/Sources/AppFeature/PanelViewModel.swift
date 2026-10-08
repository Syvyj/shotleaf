import Core
import ActionKit
import AppKit
import Observation

/// State machine for the Floating Panel: actions → (custom prompt) → generating
/// → result. Holds the snapshot captured at hotkey time and runs actions against
/// it (no re-gathering). UI flow only; business logic stays in the Kits.
@MainActor
@Observable
public final class PanelViewModel {
    public enum Screen: Equatable { case actions, customPrompt, generating, result }

    public enum Item: Identifiable {
        case action(any Action)
        case customPrompt

        public var id: String {
            switch self {
            case .action(let a): a.id
            case .customPrompt: "custom"
            }
        }
        public var title: String {
            switch self {
            case .action(let a): a.title
            case .customPrompt: "Custom Prompt"
            }
        }
    }

    public private(set) var screen: Screen = .actions
    public var selectedIndex = 0
    public var customPromptText = ""
    public private(set) var output = ""
    public private(set) var errorText: String?
    public private(set) var noticeText: String?
    public private(set) var items: [Item] = []
    /// The current provider is the canned Mock (no real model reachable).
    public var isMockProvider = false

    private let runner: ActionRunner
    private let inserter: ResultInserter
    private let accessibilityGranted: () -> Bool
    private var snapshot: ContextSnapshot?
    private var sourceApp: NSRunningApplication?
    private var streamTask: Task<Void, Never>?
    public var onClose: () -> Void = {}
    /// Called with each successful result (for History).
    public var onResult: (_ title: String, _ output: String) -> Void = { _, _ in }
    /// The custom-prompt screen is refining the current result, not the selection.
    public private(set) var isRefining = false
    private var lastRun: (action: any Action, snapshot: ContextSnapshot)?

    public init(
        runner: ActionRunner,
        inserter: ResultInserter,
        actions: [any Action],
        accessibilityGranted: @escaping () -> Bool
    ) {
        self.runner = runner
        self.inserter = inserter
        self.accessibilityGranted = accessibilityGranted
        setActions(actions)
    }

    public func setActions(_ actions: [any Action]) {
        items = actions.map { .action($0) } + [.customPrompt]
        selectedIndex = min(selectedIndex, items.count - 1)
    }

    /// What the actions will run on, so the user sees it before anything is sent:
    /// the selection, or — when nothing is selected — the clipboard.
    public var contextPreview: (source: String, text: String)? {
        if let text = snapshot?.selectedText, !text.isEmpty { return ("Selection", Self.preview(text)) }
        if let text = snapshot?.clipboardText, !text.isEmpty { return ("Clipboard", Self.preview(text)) }
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
        selectedIndex = 0
        output = ""
        errorText = nil
        noticeText = nil
        customPromptText = ""
        isRefining = false
        lastRun = nil
    }

    public func moveUp() { if screen == .actions { selectedIndex = max(0, selectedIndex - 1) } }
    public func moveDown() { if screen == .actions { selectedIndex = min(items.count - 1, selectedIndex + 1) } }

    public func confirm() {
        switch screen {
        case .actions:
            switch items[selectedIndex] {
            case .action(let action): if let snapshot { run(action, on: snapshot) }
            case .customPrompt: screen = .customPrompt
            }
        case .customPrompt:
            let text = customPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let snapshot else { return }
            // Refining works on the previous result instead of the original selection.
            let source = isRefining ? ContextSnapshot(selectedText: output, capturedAt: Date()) : snapshot
            run(CustomPromptAction(prompt: text), on: source)
        case .generating:
            break
        case .result:
            Task { await copyResult() }
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
        customPromptText = ""
        isRefining = true
        screen = .customPrompt
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

    private static func friendlyMessage(for error: Error) -> String {
        if case AppError.missingContext = error {
            return "No text found. Select some text (or copy it), then open APILA again."
        }
        if case AppError.providerUnavailable = error {
            return "No AI provider is available. Start LM Studio (or an OpenAI-compatible server), or rely on Mock."
        }
        guard let error = error as? InferenceError else { return error.localizedDescription }
        switch error {
        case .network, .timedOut, .unhealthy, .invalidURL:
            return "Can't reach the model server. Is LM Studio running with a model loaded?"
        case .noModelSelected:
            return "No model selected. Load a model in LM Studio."
        case .api(let message, _, _):
            return "Model server error: \(message)"
        case .http(let status, let body):
            return "Model server error (HTTP \(status)): \(body ?? "")"
        case .decoding:
            return "Unexpected response from the model server."
        case .cancelled:
            return "Cancelled."
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
            noticeText = "Accessibility is off — result copied to clipboard. Paste with ⌘V, or enable Accessibility in Settings to auto-paste."
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
        if screen == .customPrompt, isRefining {
            isRefining = false
            screen = .result
        } else {
            close()
        }
    }

    public func close() {
        streamTask?.cancel()
        screen = .actions
        isRefining = false
        onClose()
    }
}
