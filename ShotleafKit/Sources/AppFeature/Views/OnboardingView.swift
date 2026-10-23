import SwiftUI
import AppKit
import Core

/// First-run setup guide, built around a first result: pick the tools you want →
/// allow only what those need, each permission explained where it's used → the
/// completion model, optional → take a first screenshot → what else is there.
/// Pages that don't apply are skipped. The page is saved, so the restart that
/// follows granting a permission comes back to it.
struct OnboardingView: View {
    @Bindable var coordinator: AppCoordinator
    @AppStorage(Self.pageKey) private var pageName = Page.tools.rawValue

    static let pageKey = "setupGuidePage"

    enum Page: String, CaseIterable { case tools, permissions, model, firstShot, tour }

    private var page: Page { Page(rawValue: pageName) ?? .tools }
    private var toolsOn: [Tool] { Tool.allCases.filter(coordinator.isOn) }
    /// The permissions the chosen tools need, granted or not, screen first.
    private var needed: [PermissionKind] {
        [PermissionKind.screenRecording, .accessibility].filter { kind in toolsOn.contains { $0.permissions.contains(kind) } }
    }
    private var missing: [PermissionKind] { Tool.missing(on: toolsOn, status: coordinator.permissions) }
    private func granted(_ kind: PermissionKind) -> Bool { coordinator.permissions[kind] == .granted }
    private var modelReady: Bool { if case .ready = coordinator.modelState { true } else { false } }

    /// Whether a page has something to do; the one being shown always stays.
    private func applies(_ p: Page) -> Bool {
        switch p {
        case .tools, .tour: true
        case .permissions: !missing.isEmpty
        case .model: coordinator.isOn(.completion) && !modelReady
        case .firstShot: coordinator.isOn(.screenshots)
        }
    }
    private var pages: [Page] { Page.allCases.filter { $0 == page || applies($0) } }
    private func go(_ step: Int) {
        guard let i = pages.firstIndex(of: page), pages.indices.contains(i + step) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { pageName = pages[i + step].rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Group {
                switch page {
                case .tools: toolsPage
                case .permissions: permissionsPage
                case .model: modelPage
                case .firstShot: firstShotPage
                case .tour: tourPage
                }
            }
            .font(Leaf.font(13))
            footer
        }
        .padding(24)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true) // the window takes the wrapped height
        // Live status: permissions can change in System Settings at any moment.
        .task {
            while !Task.isCancelled {
                coordinator.refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: Frame

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Leaf.font(19, .bold))
                Text(subtitle).font(Leaf.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var title: LocalizedStringKey {
        switch page {
        case .tools: "What do you need?"
        case .permissions: "Allow what these tools need"
        case .model: "Text completion model"
        case .firstShot: "Take your first screenshot"
        case .tour: "You’re all set"
        }
    }

    private var subtitle: LocalizedStringKey {
        switch page {
        case .tools: "Turn on what you’ll use. You can change it any time in Settings › General › Features."
        case .permissions: "macOS asks you to allow these once. Nothing leaves your Mac."
        case .model: "Optional. Everything else works without it, and you can download it later in Settings › Completion."
        case .firstShot: "The quickest way to see what Shotleaf does."
        case .tour: "Everything is also in the menu bar, under the Shotleaf icon."
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if page != .tour { dots }
            Spacer()
            if page != .tools {
                Button("Back") { go(-1) }.buttonStyle(LeafButtonStyle())
            }
            if page == .tour {
                Button("Done") { coordinator.closeOnboarding() }
                    .buttonStyle(LeafButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(nextLabel) { go(1) }
                    .buttonStyle(LeafButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// "Skip for now" where something was left undone, "Continue" otherwise.
    private var nextLabel: LocalizedStringKey {
        switch page {
        case .permissions where !missing.isEmpty: "Skip for Now"
        case .model where !modelReady: "Later"
        case .firstShot where coordinator.shotsThisRun == 0: "Skip"
        default: "Continue"
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(pages, id: \.self) { p in
                Capsule().fill(p == page ? AnyShapeStyle(Leaf.markGradient) : AnyShapeStyle(.primary.opacity(0.12)))
                    .frame(width: p == page ? 18 : 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Pages

    private var toolsPage: some View {
        VStack(spacing: 8) {
            ForEach(Tool.allCases) { tool in
                Toggle(isOn: Binding(get: { coordinator.isOn(tool) }, set: { coordinator.setTool(tool, on: $0) })) {
                    HStack(spacing: 12) {
                        Image(systemName: tool.symbol).font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Leaf.ink).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(tool.title).font(Leaf.font(13, .semibold))
                                if let key = shortcut(tool) { Keycap(key: key) }
                            }
                            Text(tool.blurb).font(Leaf.font(12)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading) // every row as wide as the page
                }
                .toggleStyle(.switch)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.04)))
            }
        }
    }

    private var permissionsPage: some View {
        VStack(spacing: 10) {
            ForEach(needed, id: \.self) { kind in permissionCard(kind) }
        }
    }

    private func permissionCard(_ kind: PermissionKind) -> some View {
        let done = granted(kind)
        let users = toolsOn.filter { $0.permissions.contains(kind) }
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(kind == .screenRecording ? "Screen Recording" : "Accessibility").font(Leaf.font(14, .semibold))
                Spacer()
                if done {
                    Label("Allowed", systemImage: "checkmark.circle.fill").font(Leaf.font(12, .semibold)).foregroundStyle(Leaf.ink)
                }
            }
            Text(kind == .screenRecording
                 ? "Lets Shotleaf see the screen when you take a screenshot or copy text from one. Nothing is recorded or sent anywhere."
                 : "Lets Shotleaf paste from the history, expand snippets and type completions into other apps. It never reads password fields.")
                .fixedSize(horizontal: false, vertical: true)
            Text("For: \(users.map { String(localized: $0.titleResource) }.formatted(.list(type: .and).locale(Self.appLocale)))")
                .font(Leaf.font(12)).foregroundStyle(.secondary)
            if !done {
                HStack {
                    Button("Allow…") { Task { await coordinator.request(kind) } }
                        .buttonStyle(LeafButtonStyle(prominent: true))
                    Button("Open System Settings") { coordinator.openSettings(for: kind) }
                        .buttonStyle(LeafButtonStyle())
                }
                Text(kind == .screenRecording
                     ? "Turn Shotleaf on in the list; it restarts and brings you back here. macOS may ask you to confirm this again from time to time, which is normal for apps from outside the App Store."
                     : "Turn Shotleaf on in the list; it restarts and brings you back here.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.primary.opacity(0.04)))
    }

    private var modelPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Gemma 4 E2B, about 3.6 GB. It runs only on this Mac: what you type never leaves it.")
                .fixedSize(horizontal: false, vertical: true)
            switch coordinator.modelState {
            case .notDownloaded:
                Button("Download") { coordinator.downloadModel() }.buttonStyle(LeafButtonStyle(prominent: true))
            case .failed(let message):
                Text(message).foregroundStyle(.orange)
                Button("Try Again") { coordinator.downloadModel() }.buttonStyle(LeafButtonStyle(prominent: true))
            case .downloading(let fraction):
                HStack {
                    ProgressView(value: fraction).frame(maxWidth: 280)
                    Button("Cancel") { coordinator.cancelModelDownload() }.buttonStyle(LeafButtonStyle())
                }
                Text("It keeps downloading if you go on.").font(.caption).foregroundStyle(.secondary)
            case .ready:
                Label("Downloaded", systemImage: "checkmark.circle.fill").foregroundStyle(Leaf.ink)
            }
        }
    }

    @ViewBuilder private var firstShotPage: some View {
        if !granted(.screenRecording) {
            Text("Screenshots need Screen Recording, which isn’t allowed yet. Go back to allow it, or skip this for now.")
                .fixedSize(horizontal: false, vertical: true)
        } else if coordinator.shotsThisRun > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Label("That’s your first screenshot", systemImage: "checkmark.circle.fill")
                    .font(Leaf.font(14, .semibold)).foregroundStyle(Leaf.ink)
                Text("Mark it up with the tools at the top of the editor (hover one to see its name), then ⌘C copies it and closes the editor.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("Press")
                    Keycap(key: shortcut(.screenshots) ?? "⌘⇧2")
                    Text("or the button below, then drag over any part of the screen.")
                }
                .fixedSize(horizontal: false, vertical: true)
                Text("A click picks a window, Return takes the whole screen, Esc cancels. The editor opens with your shot.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Take a Screenshot") { coordinator.takeScreenshot() }
                    .buttonStyle(LeafButtonStyle(prominent: true))
            }
        }
    }

    private var tourPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(toolsOn) { tool in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: tool.symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(Leaf.ink).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(tool.title).font(Leaf.font(13, .semibold))
                            if let key = shortcut(tool) { Keycap(key: key) }
                        }
                        Text(tool.howTo).font(Leaf.font(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if toolsOn.isEmpty {
                Text("Every tool is off. Turn some on in Settings › General › Features.").foregroundStyle(.secondary)
            }
            Text(Self.shortcutsNote).font(Leaf.font(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            supportCard.padding(.top, 4)
        }
    }

    /// The same ask as Settings › General: what donations are for, and the button.
    private var supportCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill").font(.title2).foregroundStyle(Leaf.leaf)
            VStack(alignment: .leading, spacing: 2) {
                Text("Shotleaf is free and open source").font(Leaf.font(13, .semibold))
                Text("Donations support my time on Shotleaf and my other apps: new features, fixes and new tools.")
                    .font(Leaf.font(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Support the Author") { NSWorkspace.shared.open(AppInfo.supportPage) }
                .buttonStyle(LeafButtonStyle(prominent: true))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Leaf.leaf.opacity(0.1)))
    }

    /// The language Shotleaf shows (may differ from the system's), for joining names with "and".
    static var appLocale: Locale { Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en") }

    /// The tool's main shortcut, if it has one set.
    private func shortcut(_ tool: Tool) -> String? {
        tool.actions.first.flatMap { coordinator.actionHotkeys[$0] }?.title
    }

    /// The defaults take keys that macOS or other apps also use; say so up front.
    static let shortcutsNote: LocalizedStringKey = "⌘⇧3, ⇧⌘V and ⇧⌘B are also used by macOS (the full-screen screenshot) or by some apps. If a shortcut clashes with one you need, change it in Settings › Shortcuts."
}

extension Tool {
    var symbol: String {
        switch self {
        case .screenshots: "camera.viewfinder"
        case .screenText: "text.viewfinder"
        case .clipboard: "doc.on.clipboard"
        case .snippets: "text.badge.plus"
        case .completion: "text.cursor"
        }
    }

    /// The tool's name as a resource, for joining several into one line.
    var titleResource: LocalizedStringResource {
        switch self {
        case .screenshots: "Screenshots"
        case .screenText: "Text from Screenshot"
        case .clipboard: "Clipboard History"
        case .snippets: "Snippets"
        case .completion: "Text completion"
        }
    }

    /// What it is, for picking it.
    var blurb: LocalizedStringKey {
        switch self {
        case .screenshots: "An area, a window or the whole screen, with an editor for arrows, blur, crop and more."
        case .screenText: "Copy the words from any picture or app, recognised on your Mac."
        case .clipboard: "Everything you copied, searchable and ready to paste again."
        case .snippets: "Type a short abbreviation anywhere and get the whole text."
        case .completion: "Grey suggestions as you type, from a small model on your Mac (a 3.6 GB download)."
        }
    }

    /// How to use it, for the last page.
    var howTo: LocalizedStringKey {
        switch self {
        case .screenshots: "Drag over an area, click a window or press Return for the whole screen. The menu also has scrolling screenshots."
        case .screenText: "Select an area and its text opens, ready to copy."
        case .clipboard: "Search, then Return pastes the item into the app you were in."
        case .snippets: "Make one in the menu › Snippets › Edit Snippets…, then type its abbreviation anywhere."
        case .completion: "Type in any app. Tab takes the next word, ⌥Tab the whole suggestion."
        }
    }
}
