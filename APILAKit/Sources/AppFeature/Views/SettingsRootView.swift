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

    /// Only the permission the current vertical slice needs. Screen Recording /
    /// Input Monitoring arrive with CaptureKit — not required now.
    private let required: [PermissionKind] = [.accessibility]

    public var body: some View {
        Form {
            providerSection
            shortcutSection
            translateSection
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

    // MARK: Provider

    @ViewBuilder
    private var providerSection: some View {
        if let binding = Binding($draft) {
            Section {
                Picker("Provider", selection: kindBinding(binding)) {
                    ForEach(ProviderKind.allCases) { Text($0.displayName).tag($0) }
                }
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
                if let modelsError {
                    Text(modelsError).font(.caption).foregroundStyle(.red)
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
                Text("API keys are stored in the macOS Keychain. If the provider is unreachable, APILA falls back to Mock.")
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
            modelsError = models.isEmpty ? "The server returned no models." : nil
        } catch {
            models = []
            modelsError = "Couldn't list models: \(error)"
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
                set: { id in
                    hotkeyError = coordinator.setHotkey(id: id)
                        ? nil
                        : "\(HotkeyShortcut.with(id: id).title) is taken by another app — kept \(coordinator.hotkey.title)."
                }
            )) {
                ForEach(HotkeyShortcut.all) { Text($0.title).tag($0.id) }
            }
            if let hotkeyError {
                Text(hotkeyError).font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text("Shortcut")
        }
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
            Text("Accessibility is required for reading the selection and pasting the result. After granting, fully restart APILA.")
        }
    }

    private func title(for kind: PermissionKind) -> String {
        switch kind {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        case .inputMonitoring: "Input Monitoring"
        }
    }

    private func statusText(_ status: PermissionStatus?) -> String {
        switch status {
        case .granted: "granted"
        case .denied: "denied"
        case .notDetermined: "not determined"
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
