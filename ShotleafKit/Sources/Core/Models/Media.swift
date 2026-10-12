import Foundation

// Core stays Foundation-only: images are carried as encoded bytes + metadata,
// so the contract never leaks a platform image type into the domain.

/// An encoded image (e.g. PNG/JPEG bytes) plus its pixel dimensions and MIME type.
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
}
