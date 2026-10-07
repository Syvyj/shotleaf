import Foundation

/// Open identifier for an executor. New executors (in any module, including
/// plugins) define their own constants without editing this file.
public struct ExecutorID: Sendable, Hashable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
    public var description: String { rawValue }
}

public extension ExecutorID {
    static let inference = ExecutorID("inference")
    static let capture = ExecutorID("capture")
    static let ocr = ExecutorID("ocr")
    static let clipboard = ExecutorID("clipboard")
    static let system = ExecutorID("system")
    static let browser = ExecutorID("browser")
    static let fileSystem = ExecutorID("fileSystem")
}

/// Marker for a command handed to an executor. Each executor defines its own
/// concrete command type and casts. Open for extension — a new executor brings
/// its own command type without touching existing code.
public protocol ActionCommand: Sendable {}

/// Uniform output of ANY executor. Inference yields `.token`; an OCR executor
/// yields `.text`; a capture executor yields `.image`; etc.
public enum ActionOutput: Sendable, Equatable {
    case token(TokenChunk)
    case text(String)
    case image(ImagePayload)
    case url(URL)
    case status(String)
    case completed
}
