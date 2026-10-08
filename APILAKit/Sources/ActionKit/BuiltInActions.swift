import Core

// Built-in actions produce an ActionPlan (executor + command). Note the mix:
// most are inference actions, but `Copy` targets the clipboard executor — proof
// that Action is NOT tied to AI. Adding an action = adding a type here.

// Shared directive: chatty instruct models love to explain and offer options.
// We forbid that — the output goes straight back into the user's document.
private let outputOnly = """
Output ONLY the resulting text. Do not explain, do not offer alternatives, do not \
add a preamble, headings, quotes, or Markdown. Reply in the same language as the input.
"""

private let lowTemp = GenerationOptions(temperature: 0.2)

public struct RewriteAction: Action {
    public let id = "rewrite"
    public let title = "Rewrite"
    public let requirements = ContextRequirements(needsSelectedText: true, needsClipboard: true)
    public init() {}
    public func plan(for snapshot: ContextSnapshot) throws -> ActionPlan {
        guard snapshot.primaryText?.isEmpty == false else { throw AppError.missingContext("Rewrite needs text") }
        let template = PromptTemplate(
            system: "You are a precise editor. \(outputOnly)",
            instruction: "Rewrite the text below to be clearer and more natural, keeping its meaning, tone, and language:\n\n{{selection}}"
        )
        return ActionPlan(executor: .inference, command: InferenceCommand(template: template, options: lowTemp))
    }
}

public struct ExplainAction: Action {
    public let id = "explain"
    public let title = "Explain"
    public let requirements = ContextRequirements(needsSelectedText: true, needsClipboard: true)
    public init() {}
    public func plan(for snapshot: ContextSnapshot) throws -> ActionPlan {
        guard snapshot.primaryText?.isEmpty == false else { throw AppError.missingContext("Explain needs text") }
        let template = PromptTemplate(
            system: "You explain clearly and concisely. Reply in the same language as the input. No preamble or Markdown — just the explanation.",
            instruction: "Explain what the following means in 2–4 sentences:\n\n{{selection}}"
        )
        return ActionPlan(executor: .inference, command: InferenceCommand(template: template, options: lowTemp))
    }
}

public struct TranslateAction: Action {
    public let id = "translate"
    public let title = "Translate"
    public let requirements = ContextRequirements(needsSelectedText: true, needsClipboard: true)
    private let target: String
    private let fallback: String

    /// Translates into `target`; text already in `target` goes into `fallback`.
    public init(target: String = "English", fallback: String = "Ukrainian") {
        self.target = target
        self.fallback = fallback
    }

    public func plan(for snapshot: ContextSnapshot) throws -> ActionPlan {
        guard snapshot.primaryText?.isEmpty == false else { throw AppError.missingContext("Translate needs text") }
        let template = PromptTemplate(
            system: "You are a professional translator. Output ONLY the translation. Do not explain, do not offer alternatives, do not add a preamble, headings, quotes, or Markdown.",
            instruction: "Translate the text below into \(target). If it is already in \(target), translate it into \(fallback):\n\n{{selection}}"
        )
        return ActionPlan(executor: .inference, command: InferenceCommand(template: template, options: lowTemp))
    }
}

public struct SummarizeAction: Action {
    public let id = "summarize"
    public let title = "Summarize"
    public let requirements = ContextRequirements(needsSelectedText: true, needsClipboard: true)
    public init() {}
    public func plan(for snapshot: ContextSnapshot) throws -> ActionPlan {
        guard snapshot.primaryText?.isEmpty == false else { throw AppError.missingContext("Summarize needs text") }
        let template = PromptTemplate(
            system: "You write tight, faithful summaries. Reply in the same language as the input. No preamble — just the summary.",
            instruction: "Summarize the text below in at most 3 short bullet points:\n\n{{selection}}"
        )
        return ActionPlan(executor: .inference, command: InferenceCommand(template: template, options: lowTemp))
    }
}

/// A user-supplied instruction applied to the selection. Built at runtime with
/// the typed prompt (the panel's "Custom Prompt" entry).
public struct CustomPromptAction: Action {
    public let id = "custom"
    public let title = "Custom Prompt"
    public let requirements = ContextRequirements(needsSelectedText: true, needsClipboard: true)
    private let prompt: String

    public init(prompt: String) { self.prompt = prompt }

    public func plan(for snapshot: ContextSnapshot) throws -> ActionPlan {
        let instruction = snapshot.primaryText?.isEmpty == false
            ? "\(prompt)\n\n{{selection}}"
            : prompt
        let template = PromptTemplate(system: "You are a helpful assistant.", instruction: instruction)
        return ActionPlan(executor: .inference, command: InferenceCommand(template: template))
    }
}

// MARK: - Non-AI action (proves Action ≠ AI)

public struct CopyAction: Action {
    public let id = "copy"
    public let title = "Copy"
    public let requirements = ContextRequirements(needsSelectedText: true, needsClipboard: true)
    public init() {}
    public func plan(for snapshot: ContextSnapshot) throws -> ActionPlan {
        guard let text = snapshot.primaryText, !text.isEmpty else { throw AppError.missingContext("Copy needs text") }
        return ActionPlan(executor: .clipboard, command: ClipboardWriteCommand(text: text))
    }
}

/// The default set of actions shipped with the app.
public enum BuiltInActions {
    /// Inference actions shown in the Floating Panel picker.
    public static func inferenceActions(translateTo target: String = "English", otherwise fallback: String = "Ukrainian") -> [any Action] {
        [
            RewriteAction(),
            ExplainAction(),
            TranslateAction(target: target, fallback: fallback),
            SummarizeAction(),
        ]
    }

    public static func all() -> [any Action] {
        inferenceActions() + [CopyAction()]
    }
}
