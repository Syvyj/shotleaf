import SwiftUI
import Core
import SettingsKit

/// Settings window: shortcuts, inline completion (and its model), general,
/// permissions.
public struct SettingsRootView: View {
    @Bindable private var coordinator: AppCoordinator

    @State private var hotkeyError: String?
    @State private var showNotices = false
    @State private var confirmDeleteAll = false
    @AppStorage(Sound.key) private var sounds = true
    // Screenshots (the same keys SettingsStore reads).
    @AppStorage("afterCapture") private var afterCapture: SettingsStore.AfterCapture = .editor
    @AppStorage("saveFolder") private var saveFolder = ""
    @AppStorage("fileNameTemplate") private var fileNameTemplate = SettingsStore.defaultFileName
    @AppStorage("saveAt1x") private var saveAt1x = false
    @AppStorage("captureDelay") private var captureDelay = 0
    @AppStorage(SettingsStore.showsCursorKey) private var showsCursor = false
    @AppStorage(ScreenshotView.closeAfterCopyKey) private var closeAfterCopy = true
    /// Bumped after a tool key / order change, to redraw the list.
    @State private var toolsChanged = 0
    @State private var toolKeyError: String?

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    /// Accessibility: read the field you type in, type suggestions. Screen Recording: screenshots.
    private let required: [PermissionKind] = [.accessibility, .screenRecording]

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

    @AppStorage("settingsPane") private var pane: Pane = .general

    private var permissionsMissing: Bool {
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
    private var content: some View {
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

    private var featuresSection: some View {
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

    private var aboutSection: some View {
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
                    Button("Third-party licences") { showNotices = true }.buttonStyle(.link)
                }
            }
        }
    }

    private var supportSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill").font(.title2).foregroundStyle(Leaf.leaf)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shotleaf is free and open source").fontWeight(.semibold)
                    Text("If it helps you, support its development.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Support the Author") { NSWorkspace.shared.open(AppInfo.supportPage) }
                    .buttonStyle(LeafButtonStyle(prominent: true))
            }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return String(localized: "Version \(short) (\(build))")
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

    private var shortcutSection: some View {
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
            : String(localized: "\(shortcut!.title) is taken (by another app or another Shotleaf shortcut) — kept \(kept).")
    }

    // MARK: General

    private var generalSection: some View {
        Section {
            Toggle("Show in Dock", isOn: Binding(
                get: { coordinator.showInDock },
                set: { coordinator.setShowInDock($0) }
            ))
            Picker("Language", selection: Binding(
                get: { coordinator.language ?? "" },
                set: { coordinator.setLanguage($0.isEmpty ? nil : $0) }
            )) {
                Text("Same as macOS").tag("")
                Text(verbatim: "English").tag("en")
                Text(verbatim: "Українська").tag("uk")
            }
            Toggle("Sounds", isOn: $sounds)
            Toggle(isOn: Binding(get: { coordinator.checksForUpdates }, set: { coordinator.setChecksForUpdates($0) })) {
                Text("Check for updates automatically")
                Text("Once a day Shotleaf asks GitHub for its newest version. Nothing about you is sent.")
            }
            Toggle("Open Shotleaf at login", isOn: Binding(
                get: { coordinator.launchAtLogin },
                set: { coordinator.setLaunchAtLogin($0) }
            ))
            if let error = coordinator.launchAtLoginError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Button("Delete All Shotleaf Data…", role: .destructive) { confirmDeleteAll = true }
                .confirmationDialog("Delete all Shotleaf data?", isPresented: $confirmDeleteAll) {
                    Button("Delete and Quit", role: .destructive) { coordinator.deleteAllData() }
                } message: {
                    Text("Clipboard history, snippets, recent screenshots, your writing style, settings, the link key and the completion model. Saved screenshots stay where you saved them. This can’t be undone.")
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
            Toggle("Close the editor after copying", isOn: $closeAfterCopy)
        } header: {
            Text("Screenshots")
        }
    }

    // MARK: Links

    @AppStorage(ShotLinks.serverKey) private var linkServer = ""
    @AppStorage(ShotLinks.hoursKey) private var linkHours = 6
    @State private var linkKey = "" // read when the section shows: each Keychain read may ask for the password
    @State private var linkCheck: String?

    private var linksSection: some View {
        Section {
            TextField("Your own server", text: $linkServer, prompt: Text(verbatim: ShotLinks.freeService))
            if ShotLinks.endpoint(linkServer) != nil && linkServer != ShotLinks.freeService {
                SecureField("Key", text: $linkKey)
                    .onAppear { if linkKey.isEmpty { linkKey = ShotLinks.token ?? "" } }
                    .onChange(of: linkKey) { _, key in
                        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
                        if key != ShotLinks.token { ShotLinks.token = key }
                    }
            }
            Picker("Links work for", selection: $linkHours) {
                ForEach(ShotLinks.choices, id: \.self) { Text("\($0) h").tag($0) }
            }
            HStack {
                Button("Check") { checkLinkServer() }
                    .disabled(!linkServer.isEmpty && ShotLinks.endpoint(linkServer) == nil)
                if let linkCheck { Text(linkCheck).font(.caption).foregroundStyle(.secondary) }
            }
        } header: {
            Text("Screenshot Links")
        } footer: {
            Text("The screenshot window's link button uploads the shot and copies a link that stops working after the chosen time. Links go through Shotleaf's free service: the picture is kept on Cloudflare until the link expires, 12 hours at most. To use your own server instead (server/shots in the Shotleaf repo), enter its address and key; the key is kept in the Keychain.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Uploads a 1-pixel picture to see that the address and the key work.
    private func checkLinkServer() {
        linkCheck = String(localized: "Checking…")
        let pixel = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)?
            .representation(using: .png, properties: [:]) ?? Data()
        Task {
            do {
                let own = !linkServer.isEmpty && linkServer != ShotLinks.freeService
                let url = try await ShotLinks.upload(pixel, hours: 1, server: own ? linkServer : ShotLinks.freeService, token: own ? linkKey : nil)
                linkCheck = String(localized: "Works: \(url.host() ?? "")")
            } catch {
                linkCheck = error.localizedDescription
            }
        }
    }

    // MARK: Clipboard

    @AppStorage(ClipboardHistory.enabledKey) private var clipboardEnabled = true
    @AppStorage(ClipboardHistory.limitKey) private var clipboardLimit = 200
    @AppStorage(ClipboardHistory.imageDaysKey) private var clipboardImageDays = 30
    @AppStorage(ClipboardHistory.excludedKey) private var clipboardExcluded = ClipboardHistory.defaultExcluded.joined(separator: "\n")

    private var clipboardSection: some View {
        Section {
            Toggle(isOn: $clipboardEnabled) {
                Text("Keep clipboard history")
                Text("Only on this Mac. Passwords from password managers are never kept; card numbers and tokens are dropped after a minute.")
            }
            if clipboardEnabled {
                Picker("Keep", selection: $clipboardLimit) {
                    ForEach([50, 100, 200, 500], id: \.self) { Text("\($0) entries").tag($0) }
                }
                Picker("Images", selection: $clipboardImageDays) {
                    ForEach([7, 30, 90], id: \.self) { Text("\($0) days").tag($0) }
                }
                LabeledContent("Never keep copies from") {
                    VStack(alignment: .trailing, spacing: 4) {
                        // Defaults that aren't installed stay listed but out of sight.
                        ForEach(excludedApps.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
                            || !ClipboardHistory.defaultExcluded.contains($0) }, id: \.self) { id in
                            HStack(spacing: 6) {
                                Text(Self.appName(id)).foregroundStyle(.secondary)
                                Button { excludedApps.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless)
                            }
                        }
                        Button("Add App…") { addExcludedApp() }
                    }
                }
                Button("Clear History") { coordinator.clipboard.clear() }
            }
        } header: {
            Text("Clipboard")
        }
    }

    private var excludedApps: [String] {
        get { clipboardExcluded.split(separator: "\n").map(String.init) }
        nonmutating set { clipboardExcluded = newValue.joined(separator: "\n") }
    }

    private static func appName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { $0.deletingPathExtension().lastPathComponent } ?? bundleID
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier, !excludedApps.contains(id) else { return }
        excludedApps.append(id)
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
            Text("Accessibility lets Shotleaf complete text, expand snippets and paste from the clipboard history; Screen Recording — screenshots and text from the screen. Shotleaf restarts by itself once Accessibility is on.")
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
