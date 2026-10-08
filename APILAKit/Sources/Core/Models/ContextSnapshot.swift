import Foundation

/// An immutable snapshot of "what is happening right now" on the user's
/// machine. Built by ContextKit; consumed by ActionKit. The inference layer
/// never sees this — it only receives a finished `AIRequest`.
public struct ContextSnapshot: Sendable, Equatable {
    public let selectedText: String?
    public let clipboardText: String?
    public let activeApplication: ActiveApplication?
    public let browserURL: URL?
    public let screenImage: ImagePayload?
    /// OCR result, filled in lazily only when an Action needs screen text and
    /// the chosen provider has no vision capability.
    public let recognizedScreenText: String?
    public let capturedAt: Date

    public init(
        selectedText: String? = nil,
        clipboardText: String? = nil,
        activeApplication: ActiveApplication? = nil,
        browserURL: URL? = nil,
        screenImage: ImagePayload? = nil,
        recognizedScreenText: String? = nil,
        capturedAt: Date
    ) {
        self.selectedText = selectedText
        self.clipboardText = clipboardText
        self.activeApplication = activeApplication
        self.browserURL = browserURL
        self.screenImage = screenImage
        self.recognizedScreenText = recognizedScreenText
        self.capturedAt = capturedAt
    }

    /// Returns a copy with OCR text attached. Keeps the snapshot immutable —
    /// enrichment produces a new value rather than mutating in place.
    public func withRecognizedScreenText(_ text: String) -> ContextSnapshot {
        ContextSnapshot(
            selectedText: selectedText,
            clipboardText: clipboardText,
            activeApplication: activeApplication,
            browserURL: browserURL,
            screenImage: screenImage,
            recognizedScreenText: text,
            capturedAt: capturedAt
        )
    }

    /// Returns a copy with a captured screen image attached.
    public func withScreenImage(_ image: ImagePayload) -> ContextSnapshot {
        ContextSnapshot(
            selectedText: selectedText,
            clipboardText: clipboardText,
            activeApplication: activeApplication,
            browserURL: browserURL,
            screenImage: image,
            recognizedScreenText: nil,
            capturedAt: capturedAt
        )
    }

    /// The most relevant text the user is acting on: selection first, clipboard
    /// as fallback.
    public var primaryText: String? {
        selectedText ?? clipboardText
    }
}

/// Lightweight description of the frontmost application.
public struct ActiveApplication: Sendable, Equatable {
    public let bundleID: String?
    public let localizedName: String?
    public let processID: Int32

    public init(bundleID: String?, localizedName: String?, processID: Int32) {
        self.bundleID = bundleID
        self.localizedName = localizedName
        self.processID = processID
    }
}
