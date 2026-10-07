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
    public let items: [Item]

    private let runner: ActionRunner
    private let inserter: ResultInserter
    private let accessibilityGranted: () -> Bool
    private var snapshot: ContextSnapshot?
    private var sourceApp: NSRunningApplication?
    private var streamTask: Task<Void, Never>?
    public var onClose: () -> Void = {}

    /// Whether any text was captured (selection or clipboard).
    public var hasText: Bool { snapshot?.primaryText?.isEmpty == false }

    public init(
        runner: ActionRunner,
        inserter: ResultInserter,
        actions: [any Action],
        accessibilityGranted: @escaping () -> Bool
    ) {
        self.runner = runner
        self.inserter = inserter
        self.accessibilityGranted = accessibilityGranted
        self.items = actions.map { .action($0) } + [.customPrompt]
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
    }

    public func moveUp() { if screen == .actions { selectedIndex = max(0, selectedIndex - 1) } }
    public func moveDown() { if screen == .actions { selectedIndex = min(items.count - 1, selectedIndex + 1) } }

    public func confirm() {
        switch screen {
        case .actions:
            switch items[selectedIndex] {
            case .action(let action): run(action)
            case .customPrompt: screen = .customPrompt
            }
        case .customPrompt:
            let text = customPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            run(CustomPromptAction(prompt: text))
        case .generating:
            break
        case .result:
            Task { await copyResult() }
        }
    }

    private func run(_ action: any Action) {
        guard let snapshot else { return }
        screen = .generating
        output = ""
        errorText = nil
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
                self.errorText = Self.friendlyMessage(for: error)
            }
            self.screen = .result
        }
    }

    private static func friendlyMessage(for error: Error) -> String {
        if case AppError.missingContext = error {
            return "No text found. Select some text (or copy it), then open APILA again."
        }
        if case AppError.providerUnavailable = error {
            return "No AI provider is available. Start LM Studio (or an OpenAI-compatible server), or rely on Mock."
        }
        return "\(error)"
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

    public func close() {
        streamTask?.cancel()
        screen = .actions
        onClose()
    }
}
