import SwiftUI
import Core
import SettingsKit

/// Settings panes: Completion and Permissions.
extension SettingsRootView {
    // MARK: Completion

    var completionSection: some View {
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
        } footer: {
            Text("Never in password fields, while secure input is on (sudo, password managers), in terminals, or in the apps listed under Clipboard › Never in these apps.")
        }
    }

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
