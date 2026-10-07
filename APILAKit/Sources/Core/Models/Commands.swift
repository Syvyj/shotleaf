import Foundation

// Built-in command types. Each targets one executor. They are plain Sendable
// data — the executor that understands a command lives in its own module.

/// Run a generation. The executor resolves the provider, applies capabilities
/// (vision vs. OCR), builds the request via PromptBuilder, and streams tokens.
public struct InferenceCommand: ActionCommand {
    public let template: PromptTemplate
    public let includeScreenText: Bool
    public let options: GenerationOptions?

    public init(template: PromptTemplate, includeScreenText: Bool = false, options: GenerationOptions? = nil) {
        self.template = template
        self.includeScreenText = includeScreenText
        self.options = options
    }
}

/// Write text to the system clipboard.
public struct ClipboardWriteCommand: ActionCommand {
    public let text: String
    public init(text: String) { self.text = text }
}

/// Recognize text in an image (OCR-only action).
public struct OCRCommand: ActionCommand {
    public let image: ImagePayload
    public init(image: ImagePayload) { self.image = image }
}

/// Open a URL with the system handler.
public struct OpenURLCommand: ActionCommand {
    public let url: URL
    public init(url: URL) { self.url = url }
}
