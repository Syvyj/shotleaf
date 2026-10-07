import Foundation

/// Declares which pieces of context an Action needs. ContextKit reads this to
/// gather only what is required (privacy-first: never collect more than asked).
public struct ContextRequirements: Sendable, Equatable {
    public var needsSelectedText: Bool
    public var needsClipboard: Bool
    public var needsActiveApp: Bool
    public var needsBrowserURL: Bool
    public var needsScreenImage: Bool
    /// Action wants the textual content of the screen image. The runner decides
    /// at execution time whether to satisfy this via the provider's vision or
    /// via an OCR pass.
    public var needsScreenText: Bool

    public init(
        needsSelectedText: Bool = false,
        needsClipboard: Bool = false,
        needsActiveApp: Bool = false,
        needsBrowserURL: Bool = false,
        needsScreenImage: Bool = false,
        needsScreenText: Bool = false
    ) {
        self.needsSelectedText = needsSelectedText
        self.needsClipboard = needsClipboard
        self.needsActiveApp = needsActiveApp
        self.needsBrowserURL = needsBrowserURL
        self.needsScreenImage = needsScreenImage
        self.needsScreenText = needsScreenText
    }
}

/// A prompt template. `{{selection}}` is substituted with the primary text.
/// Kept deliberately dumb — Actions own the meaning, PromptBuilder only fills.
public struct PromptTemplate: Sendable, Equatable {
    public let system: String?
    public let instruction: String

    public init(system: String? = nil, instruction: String) {
        self.system = system
        self.instruction = instruction
    }
}
