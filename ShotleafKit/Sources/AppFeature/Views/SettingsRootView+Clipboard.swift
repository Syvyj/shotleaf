import SwiftUI
import Core
import SettingsKit

/// Settings panes: Clipboard and the editor's tools.
extension SettingsRootView {
    // MARK: Clipboard


    var clipboardSection: some View {
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
                LabeledContent {
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
                } label: {
                    Text("Never in these apps")
                    Text("No clipboard history and no text completion in them.")
                }
                Button("Clear History") { coordinator.clipboard.clear() }
            }
        } header: {
            Text("Clipboard")
        }
    }

    var excludedApps: [String] {
        get { clipboardExcluded.split(separator: "\n").map(String.init) }
        nonmutating set { clipboardExcluded = newValue.joined(separator: "\n") }
    }

    static func appName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { $0.deletingPathExtension().lastPathComponent } ?? bundleID
    }

    func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier, !excludedApps.contains(id) else { return }
        excludedApps.append(id)
    }

    // MARK: Editor tools

    var toolsSection: some View {
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

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = ScreenshotWindows.saveFolder
        if panel.runModal() == .OK, let url = panel.url { saveFolder = url.path }
    }
}
