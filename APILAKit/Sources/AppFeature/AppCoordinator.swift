import Core
import AppKit
import Observation
import SwiftUI
import ServiceManagement
import OSLog
import EmbeddedKit

/// Wires APILA together: global hotkeys → screenshots / text from a
/// screenshot / scrolling capture, inline completion and its model, settings,
/// permissions, onboarding. Pure wiring: the logic lives in the Kits and views.
@MainActor
@Observable
public final class AppCoordinator {
    private let container: AppContainer
    private var hotkeyTask: Task<Void, Never>?

    public private(set) var permissions: [PermissionKind: PermissionStatus] = [:]
    public init(container: AppContainer = AppContainer()) {
        self.container = container
    }

    public func start() async {
        applyDockPolicy()
        refreshPermissions()
        inlineCompletion.context.useScreen = container.settings.completionUsesScreen
        inlineCompletion.context.useClipboard = container.settings.completionUsesClipboard
        inlineCompletion.boldness = .init(container.settings.completionBoldness)
        inlineCompletion.quickFixes = container.settings.completionQuickFixes
        inlineCompletion.history.enabled = container.settings.completionLearnsStyle
        if container.settings.completionEnabled { inlineCompletion.start() }
        Self.log.notice("startup permissions: \(String(describing: self.permissions), privacy: .public) bundle: \(Bundle.main.bundlePath, privacy: .public)")

        let hotkeys = container.hotkeys
        for action in HotkeyAction.allCases {
            let saved = Self.savedHotkey(container.settings.hotkeyID(for: action.rawValue), default: action.defaultShortcut)
            hotkeys.setShortcut(saved, for: action.rawValue)
            actionHotkeys[action] = hotkeys.shortcut(for: action.rawValue)
        }

        // Auto-shown once; afterwards it lives in the menu ("Setup Guide…").
        if !container.settings.onboardingCompleted {
            container.settings.onboardingCompleted = true
            showOnboarding()
        }
        hotkeyTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.container.hotkeys.events {
                switch event.identifier {
                case HotkeyAction.screenshotText.rawValue: self.textFromScreenshot()
                case HotkeyAction.capture.rawValue: self.takeScreenshot()
                case HotkeyAction.scrolling.rawValue: self.takeScrollingScreenshot()
                case HotkeyAction.editLast.rawValue: self.editLastScreenshot()
                case HotkeyAction.editClipboard.rawValue: self.editClipboardImage()
                default: break
                }
            }
        }
    }

    // MARK: Screenshots

    private let screenshots = ScreenshotWindows()

    /// Shottr-style: pick a region → preview window (copy, save, pin, drag, Live Text).
    /// `delay`: seconds to wait first (with a countdown), to open a menu or
    /// tooltip that should be in the shot; nil = the default from Settings.
    public func takeScreenshot(delay: Int? = nil) {
        Task {
            let delay = delay ?? container.settings.captureDelay
            if delay > 0 { await screenshots.countdown(delay) }
            do {
                deliver(try await container.capture.captureRegion())
            } catch AppError.cancelled {
                // Esc in the picker: nothing to show.
            } catch {
                screenshots.showProblem(error)
            }
        }
    }

    /// Text from a screenshot: pick a region → its text (on-device OCR) in a
    /// small window to select, fix and copy.
    public func textFromScreenshot() {
        Task {
            do {
                let shot = try await container.capture.captureRegion()
                screenshots.showText(try await container.recognizer.recognizeText(in: shot))
            } catch AppError.cancelled {
            } catch {
                screenshots.showProblem(error)
            }
        }
    }

    /// Scrolling screenshot: pick an area, scroll it, press Done.
    public func takeScrollingScreenshot() {
        Task {
            do {
                deliver(try await container.capture.captureScrolling())
            } catch AppError.cancelled {
            } catch {
                screenshots.showProblem(error)
            }
        }
    }

    /// A new shot: into the editor, or straight to the clipboard / a file
    /// (Settings → Screenshots). Kept for "Edit Last Screenshot" either way.
    private func deliver(_ shot: ImagePayload) {
        screenshots.remember(shot)
        let after = container.settings.afterCapture
        if after == .editor { screenshots.show(shot); return }
        Sound.shutter()
        if after == .copy || after == .copyAndSave { ScreenshotWindows.copy(shot.data) }
        if after == .save || after == .copyAndSave { _ = ScreenshotWindows.save(shot.data, scale: NSScreen.main?.backingScaleFactor ?? 2) }
    }

    /// The last screenshot back in the editor (as it was taken).
    public func editLastScreenshot() {
        guard let shot = screenshots.lastCapture() else { NSSound.beep(); return }
        screenshots.show(shot, sound: false)
    }

    /// An image from the clipboard in the editor, to mark up like a screenshot.
    public func editClipboardImage() {
        guard let shot = ScreenshotWindows.clipboardImage() else { NSSound.beep(); return }
        screenshots.show(shot, sound: false)
    }

    // MARK: Settings

    /// The actions' shortcuts; missing = off.
    public private(set) var actionHotkeys: [HotkeyAction: HotkeyShortcut] = [:]

    /// Settings value → shortcut: nil = never set (default on), "off" = disabled.
    static func savedHotkey(_ saved: String?, default fallback: HotkeyShortcut) -> HotkeyShortcut? {
        switch saved {
        case nil: fallback
        case "off": nil
        case let id: .with(id: id)
        }
    }

    /// nil turns the action's hotkey off. False if the shortcut is taken.
    public func setHotkey(_ shortcut: HotkeyShortcut?, for action: HotkeyAction) -> Bool {
        let hotkeys = container.hotkeys
        let ok = hotkeys.setShortcut(shortcut, for: action.rawValue)
        if ok { container.settings.setHotkeyID(shortcut?.id ?? "off", for: action.rawValue) }
        actionHotkeys[action] = hotkeys.shortcut(for: action.rawValue)
        hotkeys.start()
        return ok
    }

    /// While recording a new shortcut the current ones must not fire (Carbon
    /// would swallow the key press and fire the action).
    public func pauseHotkey() { container.hotkeys.stop() }
    public func resumeHotkey() { container.hotkeys.start() }

    // MARK: Completion model

    public enum EmbeddedState: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready(bytes: Int64)
        case failed(String)
    }

    public private(set) var modelState: EmbeddedState =
        EmbeddedModel.completion.isDownloaded ? .ready(bytes: EmbeddedModel.completion.sizeOnDisk) : .notDownloaded

    /// Downloads (and loads) the completion model, reporting progress to Settings.
    public func downloadModel() {
        if case .downloading = modelState { return }
        modelState = .downloading(0)
        Task {
            do {
                _ = try await EmbeddedModel.completion.load { fraction in
                    Task { @MainActor [weak self] in
                        if case .downloading = self?.modelState { self?.modelState = .downloading(fraction) }
                    }
                }
                modelState = .ready(bytes: EmbeddedModel.completion.sizeOnDisk)
            } catch {
                modelState = .failed(error.localizedDescription)
            }
        }
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

    let inlineCompletion = InlineCompletion() // internal: the live test drives it

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

    // MARK: Dock

    /// Dock icon on/off: a regular app vs. a menu-bar-only (accessory) app.
    public var showInDock: Bool { container.settings.showInDock }

    public func setShowInDock(_ show: Bool) {
        container.settings.showInDock = show
        applyDockPolicy()
    }

    private func applyDockPolicy() {
        NSApp.setActivationPolicy(container.settings.showInDock ? .regular : .accessory)
    }

    /// The SwiftUI Settings scene, opened from AppKit (Dock click).
    public func openSettingsWindow() {
        NSApp.activate()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    // MARK: Launch at login

    /// Whether APILA starts at login. Real only for the installed, signed app.
    public private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    public private(set) var launchAtLoginError: String?

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Onboarding

    private var onboarding: OnboardingWindowController?

    /// The setup guide: shown once on first launch, and from the menu any time.
    public func showOnboarding() {
        let controller = onboarding ?? OnboardingWindowController { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(OnboardingView(coordinator: self))
        }
        onboarding = controller
        controller.show()
    }

    public func closeOnboarding() { onboarding?.close() }

    // MARK: Permissions (for Settings)

    public func refreshPermissions() {
        for kind in PermissionKind.allCases {
            permissions[kind] = container.permissions.status(kind)
        }
    }

    private static let log = Logger(subsystem: "app.apila.APILA", category: "permissions")

    public func request(_ kind: PermissionKind) async {
        await container.permissions.request(kind)
        refreshPermissions()
    }

    public func openSettings(for kind: PermissionKind) {
        container.permissions.openSystemSettings(for: kind)
    }
}
