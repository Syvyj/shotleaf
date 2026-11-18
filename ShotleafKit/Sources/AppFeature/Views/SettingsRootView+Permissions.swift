import SwiftUI
import Core
import SettingsKit

/// Settings pane: Permissions.
extension SettingsRootView {
    // MARK: Permissions

    var permissionsSection: some View {
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

    func title(for kind: PermissionKind) -> String {
        switch kind {
        case .accessibility: String(localized: "Accessibility")
        case .screenRecording: String(localized: "Screen Recording")
        case .inputMonitoring: String(localized: "Input Monitoring")
        }
    }

    func statusText(_ status: PermissionStatus?) -> String {
        switch status {
        case .granted: String(localized: "granted")
        case .denied: String(localized: "denied")
        case .notDetermined: String(localized: "not determined")
        case nil: "—"
        }
    }

    func color(_ status: PermissionStatus?) -> Color {
        switch status {
        case .granted: .green
        case .denied: .red
        default: .secondary
        }
    }
}
