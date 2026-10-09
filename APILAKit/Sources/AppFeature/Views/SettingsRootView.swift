import SwiftUI
import Core
import InferenceKit

/// Settings window: provider & model (key in Keychain), shortcut, translate
/// languages, permissions.
public struct SettingsRootView: View {
    @Bindable private var coordinator: AppCoordinator

    @State private var draft: AppCoordinator.ProviderSettings?
    @State private var models: [String] = []
    @State private var modelsError: String?
    @State private var isBusy = false
    @State private var hotkeyError: String?
    @State private var translateTarget = ""
    @State private var translateFallback = ""

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    /// Accessibility: read the selection, paste results. Screen Recording: screenshots.
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
                    ProviderChip(name: coordinator.currentProviderName, isMock: coordinator.providerProblem != nil)
                }
            }
            providerSection
            shortcutSection
            translateSection
            generalSection
            permissionsSection
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onAppear {
            coordinator.refreshPermissions()
            draft = coordinator.savedProviderSettings()
            (translateTarget, translateFallback) = coordinator.translateLanguages
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        return String(localized: "Version \(short)")
    }

    // MARK: Provider

    @ViewBuilder
    private var providerSection: some View {
        if let binding = Binding($draft) {
            Section {
                Picker("Provider", selection: kindBinding(binding)) {
                    ForEach(ProviderKind.allCases) { Text($0.displayName).tag($0) }
                }
                if binding.wrappedValue.kind == .embedded {
                    modelRow(.chat, about: "Gemma 4 E2B · about 3.6 GB download, runs offline, sees screenshots")
                } else {
                TextField("Base URL", text: binding.baseURL)
                if binding.wrappedValue.kind.needsAPIKey {
                    SecureField("API key", text: binding.apiKey)
                }
                HStack {
                    TextField("Model", text: binding.model)
                    if !models.isEmpty {
                        Menu("Choose") {
                            ForEach(models, id: \.self) { model in
                                Button(model) { binding.wrappedValue.model = model }
                            }
                        }
                        .fixedSize()
                    }
                    Button("Fetch models") { Task { await fetchModels() } }
                        .disabled(isBusy)
                }
                Toggle("Model can see images (screenshots)", isOn: binding.supportsVision)
                if let modelsError {
                    Text(modelsError).font(.caption).foregroundStyle(.red)
                }
                }
                HStack {
                    statusLine
                    Spacer()
                    Button("Save") { Task { await save() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isBusy || draft == coordinator.savedProviderSettings())
                }
            } header: {
                Text("Model provider")
            } footer: {
                Text("API keys are stored in the macOS Keychain. If the provider is unreachable, APILA falls back to Mock. Without image support, screenshots are sent as on-device OCR text.")
            }
        }
    }

    /// Download / progress / delete for a built-in model.
    @ViewBuilder
    private func modelRow(_ which: AppCoordinator.BuiltInModel, about: LocalizedStringKey) -> some View {
        switch coordinator.state(of: which) {
        case .notDownloaded:
            HStack {
                Text(about).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Download") { coordinator.download(which) }
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
                Button("Delete", role: .destructive) { coordinator.delete(which) }
            }
        case .failed(let message):
            HStack {
                Text("Download failed: \(message)").font(.caption).foregroundStyle(.red).lineLimit(3)
                Spacer()
                Button("Try again") { coordinator.download(which) }
            }
        }
    }

    private var statusLine: some View {
        Group {
            if let problem = coordinator.providerProblem {
                Label("\(coordinator.currentProviderName): \(problem)", systemImage: "xmark.circle")
                    .foregroundStyle(.red)
            } else {
                Label(coordinator.currentProviderName, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
        }
        .font(.caption)
        .lineLimit(2)
    }

    /// Switching kind loads that kind's key and defaults.
    private func kindBinding(_ draft: Binding<AppCoordinator.ProviderSettings>) -> Binding<ProviderKind> {
        Binding {
            draft.wrappedValue.kind
        } set: { kind in
            draft.wrappedValue = coordinator.providerSettings(for: kind, keepSavedURLAndModel: true)
            models = []
            modelsError = nil
        }
    }

    private func fetchModels() async {
        guard let draft else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            models = try await coordinator.availableModels(for: draft)
            modelsError = models.isEmpty ? String(localized: "The server returned no models.") : nil
        } catch {
            models = []
            modelsError = String(localized: "Couldn’t list models: \(error.localizedDescription)")
        }
    }

    private func save() async {
        guard let draft else { return }
        isBusy = true
        defer { isBusy = false }
        await coordinator.saveProvider(draft)
    }

    // MARK: Shortcut

    private var shortcutSection: some View {
        Section {
            Picker("Open APILA", selection: Binding(
                get: { coordinator.hotkey.id },
                set: { applyPanel(HotkeyShortcut.with(id: $0)) }
            )) {
                ForEach(panelOptions) { Text($0.title).tag($0.id) }
            }
            HotkeyRecorder(
                onStart: { hotkeyError = nil; coordinator.pauseHotkey() },
                onRecord: { applyPanel($0) },
                onCancel: { coordinator.resumeHotkey() }
            )

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

    /// Presets plus the current recorded shortcut, if any.
    private var panelOptions: [HotkeyShortcut] {
        HotkeyShortcut.all.contains(coordinator.hotkey) ? HotkeyShortcut.all : HotkeyShortcut.all + [coordinator.hotkey]
    }

    private func actionOptions(_ action: HotkeyAction) -> [HotkeyShortcut] {
        let base = [action.defaultShortcut]
        guard let current = coordinator.actionHotkeys[action], !base.contains(current) else { return base }
        return base + [current]
    }

    private func applyPanel(_ shortcut: HotkeyShortcut) {
        report(coordinator.setHotkey(shortcut), shortcut, kept: coordinator.hotkey.title)
    }

    private func applyAction(_ shortcut: HotkeyShortcut?, _ action: HotkeyAction) {
        report(coordinator.setHotkey(shortcut, for: action), shortcut, kept: coordinator.actionHotkeys[action]?.title ?? String(localized: "Off"))
    }

    private func report(_ ok: Bool, _ shortcut: HotkeyShortcut?, kept: String) {
        hotkeyError = ok || shortcut == nil
            ? nil
            : String(localized: "\(shortcut!.title) is taken (by another app or another APILA shortcut) — kept \(kept).")
    }

    // MARK: Translate

    private var translateSection: some View {
        Section {
            TextField("Translate into", text: $translateTarget)
            TextField("If already in that language, into", text: $translateFallback)
        } header: {
            Text("Translate")
        }
        .onSubmit(saveTranslate)
        .onChange(of: translateTarget) { saveTranslate() }
        .onChange(of: translateFallback) { saveTranslate() }
    }

    private func saveTranslate() {
        let target = translateTarget.trimmingCharacters(in: .whitespaces)
        let fallback = translateFallback.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty, !fallback.isEmpty else { return }
        coordinator.saveTranslate(target: target, fallback: fallback)
    }

    // MARK: General

    private var generalSection: some View {
        Section {
            Toggle("Show in Dock", isOn: Binding(
                get: { coordinator.showInDock },
                set: { coordinator.setShowInDock($0) }
            ))
            Toggle("Open APILA at login", isOn: Binding(
                get: { coordinator.launchAtLogin },
                set: { coordinator.setLaunchAtLogin($0) }
            ))
            if let error = coordinator.launchAtLoginError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Toggle(isOn: Binding(get: { coordinator.completionEnabled }, set: { coordinator.setCompletion($0) })) {
                Text("Complete my text as I type")
                Text("Grey suggestion after the cursor in any app · Tab — next word, ⌥Tab — all, esc — hide. Uses only the built-in model, on this Mac.")
            }
            if coordinator.completionEnabled {
                modelRow(.completion, about: "Completion model: Gemma 4 E2B base · about 3.6 GB, runs offline")
            }
        } header: {
            Text("General")
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
