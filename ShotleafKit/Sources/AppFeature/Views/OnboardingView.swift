import SwiftUI
import AppKit
import Core

/// First-run setup guide: permissions → completion model → try it. Each step shows live
/// status, so the user sees when it turns green.
struct OnboardingView: View {
    @Bindable var coordinator: AppCoordinator

    private var accessibilityGranted: Bool { coordinator.permissions[.accessibility] == .granted }
    private var screenGranted: Bool { coordinator.permissions[.screenRecording] == .granted }
    private var modelReady: Bool { if case .ready = coordinator.modelState { true } else { false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Shotleaf").font(Leaf.font(20, .bold))
                    Text("A few quick steps and Shotleaf works in any app.")
                        .font(Leaf.font(13))
                        .foregroundStyle(.secondary)
                }
            }

            step(1, "Allow Screen Recording", done: screenGranted) {
                Text("For screenshots and text from screenshots.")
                permissionButtons(.screenRecording, granted: screenGranted)
            }

            step(2, "Allow Accessibility", done: accessibilityGranted) {
                Text("For completing your text as you type: Shotleaf reads the field you type in and types the words you accept.")
                permissionButtons(.accessibility, granted: accessibilityGranted)
            }

            step(3, "Download the completion model", done: modelReady) {
                Text("Gemma 4 E2B base, about 3.6 GB. Runs only on this Mac — what you type never leaves it.")
                switch coordinator.modelState {
                case .notDownloaded, .failed:
                    Button("Download") { coordinator.downloadModel() }
                        .buttonStyle(LeafButtonStyle(prominent: true))
                case .downloading(let fraction):
                    ProgressView(value: fraction).frame(maxWidth: 260)
                case .ready:
                    EmptyView()
                }
            }

            step(4, "Try it", done: false) {
                Text("Take a screenshot with \(coordinator.actionHotkeys[.capture]?.title ?? "⌘⇧2"), or start typing anywhere and press Tab when a grey suggestion appears.")
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

    @ViewBuilder
    private func permissionButtons(_ kind: PermissionKind, granted: Bool) -> some View {
        HStack {
            Button("Request") { Task { await coordinator.request(kind) } }
                .buttonStyle(LeafButtonStyle(prominent: !granted))
            Button("Open System Settings") { coordinator.openSettings(for: kind) }
                .buttonStyle(LeafButtonStyle())
        }
        if !granted {
            Text("After enabling Shotleaf in the list, quit and reopen Shotleaf.")
                .font(.caption).foregroundStyle(.secondary)
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
                Text(LocalizedStringKey(title)).font(Leaf.font(14, .semibold))
                content().font(Leaf.font(12))
            }
        }
    }
}
