import Core
import AppKit
import Observation
import SwiftUI
import ServiceManagement
import OSLog
import EmbeddedKit

/// The completion model and inline completion: download, switches, start and stop.
extension AppCoordinator {
    // MARK: Completion model

    public enum EmbeddedState: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready(bytes: Int64)
        case failed(String)
    }

    /// Downloads (and loads) the completion model, reporting progress to Settings.
    /// What the download needs on disk (the model is about 3.6 GB), with room to spare.
    static let modelSpace: Int64 = 4_500_000_000

    public func downloadModel() {
        if case .downloading = modelState { return }
        let home = URL(fileURLWithPath: NSHomeDirectory())
        if let free = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           free < Self.modelSpace - EmbeddedModel.completion.sizeOnDisk {
            let need = ByteCountFormatter.string(fromByteCount: Self.modelSpace, countStyle: .file)
            let have = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
            modelState = .failed(String(localized: "Not enough free space: the model needs about \(need), \(have) is free."))
            return
        }
        modelState = .downloading(0)
        Task {
            do {
                _ = try await EmbeddedModel.completion.load { fraction in
                    Task { @MainActor in
                        if case .downloading = self.modelState { self.modelState = .downloading(fraction) }
                    }
                }
                modelState = .ready(bytes: EmbeddedModel.completion.sizeOnDisk)
            } catch {
                guard case .downloading = modelState else { return } // cancelled
                modelState = .failed(error.localizedDescription)
            }
        }
    }

    public func cancelModelDownload() {
        modelState = .notDownloaded
        Task { await EmbeddedModel.completion.cancel() }
    }

    public func deleteModel() {
        Task {
            do {
                try await EmbeddedModel.completion.delete()
                modelState = .notDownloaded
            } catch {
                modelState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Inline completion

    public var completionEnabled: Bool { container.settings.completionEnabled }

    public var completionUsesScreen: Bool { container.settings.completionUsesScreen }
    public var completionUsesClipboard: Bool { container.settings.completionUsesClipboard }

    public func setCompletionContext(screen: Bool? = nil, clipboard: Bool? = nil) {
        if let screen { container.settings.completionUsesScreen = screen; inlineCompletion.context.useScreen = screen }
        if let clipboard { container.settings.completionUsesClipboard = clipboard; inlineCompletion.context.useClipboard = clipboard }
    }

    public var completionBoldness: Double { container.settings.completionBoldness }
    public var completionQuickFixes: Bool { container.settings.completionQuickFixes }
    public var completionLearnsStyle: Bool { container.settings.completionLearnsStyle }

    public func setCompletionBoldness(_ value: Double) {
        container.settings.completionBoldness = value
        inlineCompletion.boldness = .init(value)
    }

    public func setCompletionQuickFixes(_ on: Bool) {
        container.settings.completionQuickFixes = on
        inlineCompletion.quickFixes = on
    }

    public func setCompletionLearnsStyle(_ on: Bool) {
        container.settings.completionLearnsStyle = on
        inlineCompletion.history.enabled = on
    }

    public func forgetWritingStyle() { inlineCompletion.history.forget() }

    public func setCompletion(_ on: Bool) {
        container.settings.completionEnabled = on
        if on { inlineCompletion.start() } else { inlineCompletion.stop() }
    }
}
