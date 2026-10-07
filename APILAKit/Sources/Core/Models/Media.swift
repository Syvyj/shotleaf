import Foundation

// Core stays Foundation-only: no AppKit/CoreImage. Images and audio are
// carried as encoded bytes + metadata, so the contract never leaks a
// platform image type into the domain.

/// An encoded image (e.g. PNG/JPEG bytes) plus its pixel dimensions and MIME
/// type. The MIME type is needed to build `data:` URLs for vision-capable
/// OpenAI-compatible APIs without leaking a platform image type into Core.
public struct ImagePayload: Sendable, Equatable {
    public let data: Data
    public let width: Int
    public let height: Int
    public let mimeType: String

    public init(data: Data, width: Int, height: Int, mimeType: String = "image/png") {
        self.data = data
        self.width = width
        self.height = height
        self.mimeType = mimeType
    }

    /// `data:<mime>;base64,<...>` representation for inline transport.
    public var dataURL: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }
}

/// Encoded audio (e.g. WAV/PCM bytes) plus its sample rate.
public struct AudioPayload: Sendable, Equatable {
    public let data: Data
    public let sampleRate: Int

    public init(data: Data, sampleRate: Int) {
        self.data = data
        self.sampleRate = sampleRate
    }
}

/// One part of a multimodal request. Gemma 4 E2B is quad-modal, so a request
/// is a sequence of parts, not a single string.
public enum ContentPart: Sendable, Equatable {
    case text(String)
    case image(ImagePayload)
    case audio(AudioPayload)
}
