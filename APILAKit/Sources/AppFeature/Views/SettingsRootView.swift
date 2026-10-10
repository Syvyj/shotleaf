import SwiftUI
import Core
import SettingsKit

/// Settings window: shortcuts, inline completion (and its model), general,
/// permissions.
public struct SettingsRootView: View {
    @Bindable private var coordinator: AppCoordinator

    @State private var hotkeyError: String?
    @AppStorage(Sound.key) private var sounds = true
    // Screenshots (the same keys SettingsStore reads).
    @AppStorage("afterCapture") private var afterCapture: SettingsStore.AfterCapture = .editor
    @AppStorage("saveFolder") private var saveFolder = ""
    @AppStorage("fileNameTemplate") private var fileNameTemplate = SettingsStore.defaultFileName
    @AppStorage("saveAt1x") private var saveAt1x = false
    @AppStorage("captureDelay") private var captureDelay = 0
    @AppStorage(SettingsStore.showsCursorKey) private var showsCursor = false
    /// Bumped after a tool key / order change, to redraw the list.
    @State private var toolsChanged = 0
    @State private var toolKeyError: String?

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    /// Accessibility: read the field you type in, type suggestions. Screen Recording: screenshots.
    private let required: [PermissionKind] = [.accessibility, .screenRecording]

    public var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("APILA").font(Leaf.font(16, .bold))
                        Text(Self.version).font(Leaf.font(11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            shortcutSection
            screenshotSection
            toolsSection
            completionSection
            generalSection
            permissionsSection
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onAppear {
            coordinator.refreshPermissions()
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        return String(localized: "Version \(short)")
    }

    // MARK: Completion model

    /// Download / progress / delete for the completion model.
    @ViewBuilder
    private func modelRow(about: LocalizedStringKey) -> some View {
        switch coordinator.modelState {
        case .notDownloaded:
            HStack {
                Text(about).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Download") { coordinator.downloadModel() }
            }
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: fraction)
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

    private var shortcutSection: some View {
        Section {
            ForEach(HotkeyAction.allCases) { action in
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
        }
    }

    private func actionOptions(_ action: HotkeyAction) -> [HotkeyShortcut] {
        let base = [action.defaultShortcut]
        guard let current = coordinator.actionHotkeys[action], !base.contains(current) else { return base }
        return base + [current]
    }

    private func applyAction(_ shortcut: HotkeyShortcut?, _ action: HotkeyAction) {
        report(coordinator.setHotkey(shortcut, for: action), shortcut, kept: coordinator.actionHotkeys[action]?.title ?? String(localized: "Off"))
    }

    private func report(_ ok: Bool, _ shortcut: HotkeyShortcut?, kept: String) {
        hotkeyError = ok || shortcut == nil
            ? nil
            : String(localized: "\(shortcut!.title) is taken (by another app or another APILA shortcut) — kept \(kept).")
    }

    // MARK: General

    private var generalSection: some View {
        Section {
            Toggle("Show in Dock", isOn: Binding(
                get: { coordinator.showInDock },
                set: { coordinator.setShowInDock($0) }
            ))
            Toggle("Sounds", isOn: $sounds)
            Toggle("Open APILA at login", isOn: Binding(
                get: { coordinator.launchAtLogin },
                set: { coordinator.setLaunchAtLogin($0) }
            ))
            if let error = coordinator.launchAtLoginError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("General")
        }
    }

    // MARK: Screenshots

    private var screenshotSection: some View {
        Section {
            Picker("After a screenshot", selection: $afterCapture) {
                Text("Open the editor").tag(SettingsStore.AfterCapture.editor)
                Text("Copy").tag(SettingsStore.AfterCapture.copy)
                Text("Save").tag(SettingsStore.AfterCapture.save)
                Text("Copy and save").tag(SettingsStore.AfterCapture.copyAndSave)
            }
            LabeledContent("Save to") {
                HStack {
                    Text(saveFolder.isEmpty ? String(localized: "Desktop") : (saveFolder as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Button("Choose…") { chooseFolder() }
                    if !saveFolder.isEmpty { Button("Desktop") { saveFolder = "" } }
                }
            }
            LabeledContent {
                TextField("", text: $fileNameTemplate, prompt: Text(verbatim: SettingsStore.defaultFileName))
                    .frame(width: 220)
            } label: {
                Text("File name")
                Text("{date} and {time} are filled in: \(ScreenshotWindows.fileName(Date(), template: fileNameTemplate))")
            }
            Toggle(isOn: $saveAt1x) {
                Text("Save at 1x")
                Text("Retina shots are saved at half the pixels — smaller files.")
            }
            Picker("Delay", selection: $captureDelay) {
                Text("Off").tag(0)
                Text(verbatim: "3 s").tag(3)
                Text(verbatim: "5 s").tag(5)
                Text(verbatim: "10 s").tag(10)
            }
            .pickerStyle(.segmented)
            Toggle("Include the pointer", isOn: $showsCursor)
        } header: {
            Text("Screenshots")
        }
    }

    // MARK: Editor tools

    private var toolsSection: some View {
        Section {
            let _ = toolsChanged
            let tools = AnnotationTool.ordered
            ForEach(Array(tools.enumerated()), id: \.element) { i, tool in
                HStack(spacing: 10) {
                    ToolIcon(tool: tool, size: 16).frame(width: 20)
                    Text(tool.title)
                    Spacer()
                    TextField("", text: Binding(
                        get: { tool.key.map { String($0).uppercased() } ?? "" },
                        set: { typed in
                            toolKeyError = ToolPrefs.setKey(typed, for: tool) ? nil
                                : String(localized: "P, T and 0 are taken by the editor itself.")
                            toolsChanged += 1
                        }
                    ), prompt: Text("—"))
                    .multilineTextAlignment(.center)
                    .frame(width: 44)
                    Button { ToolPrefs.move(tool, by: -1); toolsChanged += 1 } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless).disabled(i == 0)
                    Button { ToolPrefs.move(tool, by: 1); toolsChanged += 1 } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.borderless).disabled(i == tools.count - 1)
                }
            }
            if let toolKeyError { Text(toolKeyError).font(.caption).foregroundStyle(.orange) }
            Button("Reset keys and order") { ToolPrefs.reset(); toolKeyError = nil; toolsChanged += 1 }
        } header: {
            Text("Editor tools")
        } footer: {
            Text("Type a key for a tool; a tool already on it gives it up. Empty — no key. Arrow, box and oval share one button.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = ScreenshotWindows.saveFolder
        if panel.runModal() == .OK, let url = panel.url { saveFolder = url.path }
    }

    // MARK: Completion

    private var completionSection: some View {
        Section {
            Toggle(isOn: Binding(get: { coordinator.completionEnabled }, set: { coordinator.setCompletion($0) })) {
                Text("Complete my text as I type")
                Text("Grey suggestion after the cursor in any app · Tab — next word, ⌥Tab — all, esc — hide. Uses only the built-in model, on this Mac.")
            }
            if coordinator.completionEnabled {
                modelRow(about: "Completion model: Gemma 4 E2B base · about 3.6 GB, runs offline")
                Toggle(isOn: Binding(get: { coordinator.completionUsesScreen }, set: { coordinator.setCompletionContext(screen: $0) })) {
                    Text("Use text on screen")
                    Text("Reads the window you type in (the chat, the page) so suggestions fit. On this Mac only; needs Screen Recording.")
                }
                Toggle(isOn: Binding(get: { coordinator.completionUsesClipboard }, set: { coordinator.setCompletionContext(clipboard: $0) })) {
                    Text("Use what I just copied")
                    Text("Text copied in the last 5 minutes.")
                }
                LabeledContent {
                    HStack {
                        Text("Cautious").font(.caption).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { coordinator.completionBoldness }, set: { coordinator.setCompletionBoldness($0) }), in: 0...1)
                        Text("Bold").font(.caption).foregroundStyle(.secondary)
                    }
                } label: {
                    Text("Suggestions")
                    Text("Cautious: only sure, short ones. Bold: more often and longer.")
                }
                Toggle(isOn: Binding(get: { coordinator.completionQuickFixes }, set: { coordinator.setCompletionQuickFixes($0) })) {
                    Text("Emoji and spelling fixes")
                    Text("Type : or ; for an emoji picker (1–9 or a click; letters filter, :fire → 🔥). A misspelled word gets a fix with Tab.")
                }
                Toggle(isOn: Binding(get: { coordinator.completionLearnsStyle }, set: { coordinator.setCompletionLearnsStyle($0) })) {
                    Text("Learn my style")
                    Text("Remembers a few of your own texts per app, only on this Mac, so suggestions sound like you.")
                }
                Button("Forget what I wrote") { coordinator.forgetWritingStyle() }
            }
        } header: {
            Text("Completion")
        }
    }

    // MARK: Permissions

    private var permissionsSection: some View {
        Section {
            ForEach(required, id: \.self) { kind in
                HStack {
                    Text(title(for: kind))
                    Spacer()
                    Text(statusText(coordinator.permissions[kind]))
                        .foregroundStyle(color(coordinator.permissions[kind]))
                        .monospaced()
                    Button("Request") { Task { await coordinator.request(kind) } }
                    Button("Open Settings") { coordinator.openSettings(for: kind) }
                }
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text("Accessibility is required for reading the selection and pasting the result; Screen Recording — for screenshots. After granting, fully restart APILA.")
        }
    }

    private func title(for kind: PermissionKind) -> String {
        switch kind {
        case .accessibility: String(localized: "Accessibility")
        case .screenRecording: String(localized: "Screen Recording")
        case .inputMonitoring: String(localized: "Input Monitoring")
        }
    }

    private func statusText(_ status: PermissionStatus?) -> String {
        switch status {
        case .granted: String(localized: "granted")
        case .denied: String(localized: "denied")
        case .notDetermined: String(localized: "not determined")
        case nil: "—"
        }
    }

    private func color(_ status: PermissionStatus?) -> Color {
        switch status {
        case .granted: .green
        case .denied: .red
        default: .secondary
        }
    }
}
