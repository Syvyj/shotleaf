import SwiftUI

/// The Floating Panel UI. Fully keyboard-first: ↑↓ navigate, ⏎ confirm, esc close,
/// ⌘C/⌘R/⌘I on the result. Translucent material background.
public struct PanelView: View {
    @Bindable private var vm: PanelViewModel
    @FocusState private var promptFocused: Bool

    public init(vm: PanelViewModel) { self.vm = vm }

    public var body: some View {
        ZStack {
            content
            shortcuts
        }
        .frame(width: 460)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var content: some View {
        switch vm.screen {
        case .actions: actionsScreen
        case .customPrompt: customPromptScreen
        case .generating: generatingScreen
        case .result: resultScreen
        }
    }

    // MARK: Screens

    private var actionsScreen: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                header("APILA")
                Spacer()
                if vm.isMockProvider {
                    Label("Mock — no model connected", systemImage: "bolt.horizontal.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if !vm.hasText {
                Label("No text captured — select text, or copy it first.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12).padding(.bottom, 4)
            }
            ForEach(Array(vm.items.enumerated()), id: \.element.id) { index, item in
                HStack {
                    Text(item.title)
                    Spacer()
                    if index == vm.selectedIndex {
                        Image(systemName: "return").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(
                    index == vm.selectedIndex ? Color.accentColor.opacity(0.25) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .contentShape(Rectangle())
                .onTapGesture { vm.selectedIndex = index; vm.confirm() }
            }
            hint("↑↓ navigate · ⏎ select · esc close")
        }
        .padding(12)
    }

    private var customPromptScreen: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Custom Prompt")
            TextField("Describe what to do with the selection…", text: $vm.customPromptText)
                .textFieldStyle(.plain)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .focused($promptFocused)
                .onSubmit { vm.confirm() }
            hint("⏎ run · esc cancel")
        }
        .padding(12)
        .onAppear { promptFocused = true }
    }

    private var generatingScreen: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Generating…").foregroundStyle(.secondary)
            }
            ScrollView {
                Text(vm.output.isEmpty ? " " : vm.output)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 220)
            hint("esc cancel")
        }
        .padding(12)
    }

    private var resultScreen: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Result")
            ScrollView {
                Text(vm.errorText ?? vm.output)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .foregroundStyle(vm.errorText == nil ? Color.primary : Color.red)
            }
            .frame(maxHeight: 240)
            Divider()
            HStack {
                Button("Copy") { Task { await vm.copyResult() } }
                    .keyboardShortcut("c", modifiers: .command)
                Button("Replace") { Task { await vm.replaceSelection() } }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Insert Below") { Task { await vm.insertBelow() } }
                    .keyboardShortcut("i", modifiers: .command)
                Spacer()
                Button("Close") { vm.close() }
            }
            if let notice = vm.noticeText {
                Text(notice).font(.caption).foregroundStyle(.orange)
            }
            hint("⌘C copy · ⌘R replace · ⌘I insert · esc close")
        }
        .padding(12)
    }

    // MARK: Hidden keyboard handlers (active while the panel is key)

    @ViewBuilder
    private var shortcuts: some View {
        VStack {
            Button("") { vm.close() }.keyboardShortcut(.cancelAction)
            switch vm.screen {
            case .actions:
                Button("") { vm.confirm() }.keyboardShortcut(.defaultAction)
                Button("") { vm.moveUp() }.keyboardShortcut(.upArrow, modifiers: [])
                Button("") { vm.moveDown() }.keyboardShortcut(.downArrow, modifiers: [])
            case .result:
                Button("") { Task { await vm.copyResult() } }.keyboardShortcut(.defaultAction)
            default:
                EmptyView()
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.headline).padding(.bottom, 2)
    }
    private func hint(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
    }
}
