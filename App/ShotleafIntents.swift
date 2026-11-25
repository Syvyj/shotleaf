import AppIntents
import AppFeature
import Core
import UniformTypeIdentifiers

/// The size limits Save as offers (`SmallFile.limits`), for Shortcuts.
enum SizeLimit: Int, AppEnum {
    case kb200 = 200_000, kb500 = 500_000, mb1 = 1_000_000, mb8 = 8_000_000, mb25 = 25_000_000

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Size Limit"
    static let caseDisplayRepresentations: [SizeLimit: DisplayRepresentation] = [
        .kb200: "200 KB", .kb500: "500 KB", .mb1: "1 MB", .mb8: "8 MB", .mb25: "25 MB",
    ]
}

/// A file in → a JPEG under the chosen size out (any picture ImageIO reads).
struct CompressImageIntent: AppIntent {
    static let title: LocalizedStringResource = "Compress Image"
    static let description = IntentDescription("Makes a JPEG of a picture that fits under the chosen size.")
    static let openAppWhenRun = false

    @Parameter(title: "Image", supportedContentTypes: [.image])
    var image: IntentFile

    @Parameter(title: "Size Limit", default: .mb1)
    var limit: SizeLimit

    static var parameterSummary: some ParameterSummary {
        Summary("Compress \(\.$image) under \(\.$limit)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        var source = image.fileURL
        if source == nil { // Shortcuts may hand over the bytes alone
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            source = folder.appendingPathComponent(image.filename)
            try image.data.write(to: source!)
        }
        let jpeg = try await SmallFile.compressFile(source!, under: limit.rawValue)
        return .result(value: IntentFile(fileURL: jpeg, filename: jpeg.lastPathComponent, type: .jpeg))
    }
}

/// Picks an area like ⌘⇧2 and returns its PNG (no preview window).
struct CaptureAreaIntent: AppIntent {
    static let title: LocalizedStringResource = "Screenshot an Area"
    static let description = IntentDescription("Lets you pick an area of the screen and returns it as a PNG.")
    static let openAppWhenRun = true // the area picker needs Shotleaf active

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard let coordinator = AppCoordinator.shared else { throw ShortcutError.notRunning }
        do {
            let png = try await coordinator.captureForShortcut()
            return .result(value: IntentFile(data: png, filename: "Screenshot.png", type: .png))
        } catch AppError.cancelled {
            throw ShortcutError.cancelled // Esc: end the shortcut, don't hang
        }
    }
}

enum ShortcutError: Error, CustomLocalizedStringResourceConvertible {
    case cancelled, notRunning

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .cancelled: "The screenshot was cancelled."
        case .notRunning: "Shotleaf isn't ready yet. Try again."
        }
    }
}

struct ShotleafShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CaptureAreaIntent(), phrases: ["Screenshot an area with \(.applicationName)"],
                    shortTitle: "Screenshot an Area", systemImageName: "viewfinder")
        AppShortcut(intent: CompressImageIntent(), phrases: ["Compress an image with \(.applicationName)"],
                    shortTitle: "Compress Image", systemImageName: "arrow.down.right.and.arrow.up.left")
    }
}
