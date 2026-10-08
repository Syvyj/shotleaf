import SwiftUI
import AppKit
import Core

/// First-run setup guide: permission → model → try it. Each step shows live
/// status, so the user sees when it turns green.
struct OnboardingView: View {
    @Bindable var coordinator: AppCoordinator

    private var accessibilityGranted: Bool { coordinator.permissions[.accessibility] == .granted }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to APILA").font(Leaf.font(20, .bold))
                    Text("Three quick steps and APILA works in any app.")
                        .font(Leaf.font(13))
                        .foregroundStyle(.secondary)
                }
            }

            step(1, "Allow Accessibility", done: accessibilityGranted) {
                Text("Needed to read your selection and paste results back.")
                HStack {
                    Button("Request") { Task { await coordinator.request(.accessibility) } }
                        .buttonStyle(LeafButtonStyle(prominent: !accessibilityGranted))
                    Button("Open System Settings") { coordinator.openSettings(for: .accessibility) }
                        .buttonStyle(LeafButtonStyle())
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
                        .buttonStyle(LeafButtonStyle())
                    Button("Check again") { Task { await coordinator.refreshProvider() } }
                        .buttonStyle(LeafButtonStyle())
                }
            }

            step(3, "Try it", done: !coordinator.history.isEmpty) {
                Text("Select some text in any app and press \(coordinator.hotkey.title).")
            }

            HStack {
                Spacer()
                Button("Done") { coordinator.closeOnboarding() }
                    .buttonStyle(LeafButtonStyle(prominent: true))
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
            ZStack {
                Circle()
                    .fill(done ? AnyShapeStyle(Leaf.accent) : AnyShapeStyle(.primary.opacity(0.07)))
                    .frame(width: 26, height: 26)
                if done {
                    SparkMark().fill(Leaf.forest).frame(width: 12, height: 12)
                } else {
                    Text("\(number)").font(Leaf.font(12, .bold)).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Leaf.font(14, .semibold))
                content().font(Leaf.font(12))
            }
        }
    }
}
