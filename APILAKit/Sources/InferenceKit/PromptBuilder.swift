import Core

/// A deliberately small assembler — NOT a God Object. It fills a template and
/// decides image-vs-OCR attachment based on provider capabilities. Lives in
/// InferenceKit because it is inference-specific; the *meaning* of an action
/// still lives in the Action.
public struct PromptBuilder: Sendable {
    public init() {}

    public func buildRequest(
        template: PromptTemplate,
        snapshot: ContextSnapshot,
        capabilities: ProviderCapabilities,
        options: GenerationOptions? = nil,
        preferredProviderID: String? = nil
    ) -> AIRequest {
        var parts: [ContentPart] = []

        let selection = Self.fit(snapshot.primaryText ?? "", contextTokens: capabilities.maxContextTokens)
        let rendered = template.instruction.replacingOccurrences(of: "{{selection}}", with: selection)
        parts.append(.text(rendered))

        // Multimodal decision: prefer native vision, otherwise OCR text.
        if capabilities.supportsVision, let image = snapshot.screenImage {
            parts.append(.image(image))
        } else if let ocr = snapshot.recognizedScreenText, !ocr.isEmpty {
            parts.append(.text("Screen text:\n\(ocr)"))
        }

        return AIRequest(system: template.system, parts: parts, preferredProviderID: preferredProviderID, options: options)
    }

    static let truncationMarker = "\n[…truncated]"

    /// Keeps the selection within about half the context window, leaving room
    /// for the instruction and the reply.
    /// ponytail: ~4 chars/token estimate, no tokenizer; under-counts for CJK/code.
    static func fit(_ text: String, contextTokens: Int) -> String {
        let maxChars = contextTokens * 2
        guard text.count > maxChars else { return text }
        return String(text.prefix(maxChars)) + truncationMarker
    }
}
