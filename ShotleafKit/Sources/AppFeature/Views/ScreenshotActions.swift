import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// What the screenshot window can do; wired by `ScreenshotWindows`. Copy,
/// save, pin and drag use the screenshot *with* its annotations.
struct ScreenshotActions {
    var copy: () -> Void
    var save: () -> URL?
    var pin: () -> Void
    var close: () -> Void
    /// A PNG file of the current result, for drag-and-drop into other apps.
    var dragFile: () -> URL?
    /// "Save as…" in another format (asks where).
    var saveAs: (UTType) -> Void = { _ in }
    /// "JPEG under 1 MB…": a smaller file for mail and chats (asks where).
    var saveSmall: (Int) -> Void = { _ in }
    /// Uploads the result to the link server; the link lives that many hours.
    var link: (Int) async throws -> URL = { _ in throw ShotLinks.Failure.notSetUp }
    /// The system share menu (AirDrop, Messages, Mail…).
    var share: () -> Void = {}
    /// Keeps the result as a snippet (in the folder last opened); that folder's name, if any.
    var toSnippets: () -> String? = { nil }
}
