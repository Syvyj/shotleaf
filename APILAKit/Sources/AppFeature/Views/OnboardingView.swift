import SwiftUI
import Core

/// First-run setup guide: permission → model → try it. Each step shows live
/// status, so the user sees when it turns green.
struct OnboardingView: View {
    @Bindable var coordinator: AppCoordinator

    private var accessibilityGranted: Bool { coordinator.permissions[.accessibility] == .granted }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Three quick steps and APILA works in any app.")
                .foregroundStyle(.secondary)

            step(1, "Allow Accessibility", done: accessibilityGranted) {
                Text("Needed to read your selection and paste results back.")
                HStack {
                    Button("Request") { Task { await coordinator.request(.accessibility) } }
                    Button("Open System Settings") { coordinator.openSettings(for: .accessibility) }
                }
                if !accessibilityGranted {
                    Text("After enabling APILA in the list, quit and reopen APILA.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            step(2, "Connect a model", done: coordinator.providerProblem == nil) {
                Text(coordinator.providerProblem == nil
                     ? "Using \(coordinator.currentProviderName)."
                     : "Start LM Studio (or Ollama) with a model loaded, or add an OpenAI / OpenRouter key in Settings.")
                HStack {
                    SettingsLink { Text("Open Settings…") }
                    Button("Check again") { Task { await coordinator.refreshProvider() } }
                }
            }

            step(3, "Try it", done: !coordinator.history.isEmpty) {
                Text("Select some text in any app and press \(coordinator.hotkey.title).")
            }

            HStack {
                Spacer()
                Button("Done") { coordinator.closeOnboarding() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        // Live status: permissions can change in System Settings at any moment.
        .task {
            while !Task.isCancelled {
                coordinator.refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func step<Content: View>(
        _ number: Int, _ title: String, done: Bool, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2)
                .foregroundStyle(done ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                content()
            }
        }
    }
}
