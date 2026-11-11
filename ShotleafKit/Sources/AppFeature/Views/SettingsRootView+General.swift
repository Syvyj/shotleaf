import SwiftUI
import Core
import SettingsKit

/// Settings panes: General, Screenshots and Screenshot Links.
extension SettingsRootView {
    // MARK: General

    var generalSection: some View {
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

    var screenshotSection: some View {
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


    var linksSection: some View {
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
    func checkLinkServer() {
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
}
