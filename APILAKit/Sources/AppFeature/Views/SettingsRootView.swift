import SwiftUI
import Core

/// Settings window. For this iteration: live permission status + request/open
/// buttons. Provider/model configuration UI lands with SettingsKit wiring.
public struct SettingsRootView: View {
    @Bindable private var coordinator: AppCoordinator

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    /// Only the permission the current vertical slice needs. Screen Recording /
    /// Input Monitoring arrive with CaptureKit — not required now.
    private let required: [PermissionKind] = [.accessibility]

    public var body: some View {
        Form {
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
        .formStyle(.grouped)
        .frame(width: 480, height: 200)
        .onAppear { coordinator.refreshPermissions() }
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
