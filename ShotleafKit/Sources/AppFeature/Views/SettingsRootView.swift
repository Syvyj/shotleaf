import SwiftUI
import Core
import SettingsKit

/// Settings window: shortcuts, inline completion (and its model), general,
/// permissions.
public struct SettingsRootView: View {
    @Bindable var coordinator: AppCoordinator

    @State var hotkeyError: String?
    @State var showNotices = false
    @State var confirmDeleteAll = false
    @AppStorage(Sound.key) var sounds = true
    // Screenshots (the same keys SettingsStore reads).
    @AppStorage("afterCapture") var afterCapture: SettingsStore.AfterCapture = .editor
    @AppStorage("saveFolder") var saveFolder = ""
    @AppStorage("fileNameTemplate") var fileNameTemplate = SettingsStore.defaultFileName
    @AppStorage("saveAt1x") var saveAt1x = false
    @AppStorage("captureDelay") var captureDelay = 0
    @AppStorage(SettingsStore.showsCursorKey) var showsCursor = false
    @AppStorage(ScreenshotView.closeAfterCopyKey) var closeAfterCopy = true
    /// Bumped after a tool key / order change, to redraw the list.
    @State var toolsChanged = 0
    @State var toolKeyError: String?

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    /// Accessibility: read the field you type in, type suggestions. Screen Recording: screenshots.
    let required: [PermissionKind] = [.accessibility, .screenRecording]

    /// The sidebar's panes.
    enum Pane: String, CaseIterable, Identifiable {
        case general, shortcuts, screenshots, tools, clipboard, completion, permissions
        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .general: "General"
            case .shortcuts: "Shortcuts"
            case .screenshots: "Screenshots"
            case .tools: "Tools"
            case .clipboard: "Clipboard"
            case .completion: "Completion"
            case .permissions: "Permissions"
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .shortcuts: "keyboard"
            case .screenshots: "camera.viewfinder"
            case .tools: "pencil.tip.crop.circle"
            case .clipboard: "doc.on.clipboard"
            case .completion: "text.cursor"
            case .permissions: "lock.shield"
            }
        }
    }

    @AppStorage("settingsPane") var pane: Pane = .general

    var permissionsMissing: Bool {
        required.contains { coordinator.permissions[$0] != .granted }
    }

    public var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: Binding(get: { pane }, set: { if let new = $0 { pane = new } })) { pane in
                Label {
                    HStack {
                        Text(pane.title)
                        if pane == .permissions && permissionsMissing {
                            Spacer()
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                        }
                    }
                } icon: {
                    Image(systemName: pane.icon)
                }
                .tag(pane)
            }
            .frame(minWidth: 220) // the Settings window ignores the column width below and opened it at 144 pt, cutting the names
            .navigationSplitViewColumnWidth(240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Form { content }
                .formStyle(.grouped)
                .navigationTitle(Text(pane.title))
        }
        .sheet(isPresented: $showNotices) { ThirdPartyNoticesView { showNotices = false } }
        .frame(width: 800, height: 600)
        .onAppear {
            coordinator.refreshPermissions()
        }
    }

    @ViewBuilder
    var content: some View {
        switch pane {
        case .general:
            aboutSection
            supportSection
            featuresSection
            generalSection
        case .shortcuts: shortcutSection
        case .screenshots:
            screenshotSection
            linksSection
        case .tools: toolsSection
        case .clipboard: clipboardSection
        case .completion: completionSection
        case .permissions: permissionsSection
        }
    }

    var featuresSection: some View {
        Section {
            ForEach(Tool.allCases) { tool in
                Toggle(tool.title, isOn: Binding(get: { coordinator.isOn(tool) }, set: { coordinator.setTool(tool, on: $0) }))
            }
        } header: {
            Text("Features")
        } footer: {
            Text("A tool you turn off leaves the menu, frees its shortcuts and stops working in the background. Its settings and data stay.")
        }
    }

    var aboutSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: AppInfo.name).font(Leaf.font(18, .bold))
                    Text(Self.version).foregroundStyle(.secondary)
                    if let update = coordinator.update {
                        Button("Version \(update.version) is out: update") { coordinator.installUpdate() }
                            .buttonStyle(.link).fontWeight(.semibold).disabled(coordinator.updating)
                    }
                    Text(verbatim: AppInfo.copyright).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Link("syvyj.dev", destination: AppInfo.website)
                    Link(AppInfo.email, destination: URL(string: "mailto:\(AppInfo.email)")!)
                    Link("Privacy", destination: AppInfo.privacyPage)
                    Link("Report a problem", destination: AppInfo.newIssue)
                    Button("Third-party licences") { showNotices = true }.buttonStyle(.link)
                }
            }
        }
    }

    var supportSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill").font(.title2).foregroundStyle(Leaf.leaf)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shotleaf is free and open source").fontWeight(.semibold)
                    Text("Donations support my time on Shotleaf and my other apps: new features, fixes and new tools.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Support the Author") { NSWorkspace.shared.open(AppInfo.supportPage) }
                    .buttonStyle(LeafButtonStyle(prominent: true))
            }
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return String(localized: "Version \(short) (\(build))")
    }

    // MARK: Completion model

    /// Download / progress / delete for the completion model.
    @ViewBuilder
    func modelRow(about: LocalizedStringKey) -> some View {
        switch coordinator.modelState {
        case .notDownloaded:
            HStack {
                Text(about).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Download") { coordinator.downloadModel() }
            }
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    ProgressView(value: fraction)
                    Button("Cancel") { coordinator.cancelModelDownload() }
                }
                Text(fraction < 1 ? String(localized: "Downloading… \(Int(fraction * 100))%") : String(localized: "Loading the model…"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .ready(let bytes):
            HStack {
                Label("Downloaded · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                Spacer()
                Button("Delete", role: .destructive) { coordinator.deleteModel() }
            }
        case .failed(let message):
            HStack {
                Text("Download failed: \(message)").font(.caption).foregroundStyle(.red).lineLimit(3)
                Spacer()
                Button("Try again") { coordinator.downloadModel() }
            }
        }
    }

    // MARK: Shortcut

    var shortcutSection: some View {
        Section {
            ForEach(HotkeyAction.allCases.filter { Tool.owning($0).map(coordinator.isOn) ?? true }) { action in
                Picker(action.title, selection: Binding(
                    get: { coordinator.actionHotkeys[action]?.id ?? "off" },
                    set: { applyAction($0 == "off" ? nil : HotkeyShortcut.with(id: $0), action) }
                )) {
                    Text("Off").tag("off")
                    ForEach(actionOptions(action)) { Text($0.title).tag($0.id) }
                }
                HotkeyRecorder(
                    onStart: { hotkeyError = nil; coordinator.pauseHotkey() },
                    onRecord: { applyAction($0, action) },
                    onCancel: { coordinator.resumeHotkey() }
                )
            }

            if let hotkeyError {
                Text(hotkeyError).font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text("Shortcuts")
        } footer: {
            Text(OnboardingView.shortcutsNote)
        }
    }

    func actionOptions(_ action: HotkeyAction) -> [HotkeyShortcut] {
        let base = [action.defaultShortcut]
        guard let current = coordinator.actionHotkeys[action], !base.contains(current) else { return base }
        return base + [current]
    }

    func applyAction(_ shortcut: HotkeyShortcut?, _ action: HotkeyAction) {
        report(coordinator.setHotkey(shortcut, for: action), shortcut, kept: coordinator.actionHotkeys[action]?.title ?? String(localized: "Off"))
    }

    func report(_ ok: Bool, _ shortcut: HotkeyShortcut?, kept: String) {
        hotkeyError = ok || shortcut == nil
            ? nil
            : String(localized: "\(shortcut!.title) is taken (by another app or another Shotleaf shortcut) — kept \(kept).")
    }

    @AppStorage(ClipboardHistory.enabledKey) var clipboardEnabled = true
    @AppStorage(ClipboardHistory.limitKey) var clipboardLimit = ClipboardHistory.defaultLimit
    @AppStorage(ClipboardHistory.imageDaysKey) var clipboardImageDays = ClipboardHistory.defaultImageDays
    @AppStorage(ClipboardHistory.excludedKey) var clipboardExcluded = ClipboardHistory.defaultExcluded.joined(separator: "\n")

    @AppStorage(ShotLinks.serverKey) var linkServer = ""
    @AppStorage(ShotLinks.hoursKey) var linkHours = 6
    @State var linkKey = "" // read when the section shows: each Keychain read may ask for the password
    @State var linkCheck: String?
}
