import SwiftUI

/// The Floating Panel UI, in the "Leaves" style. Fully keyboard-first:
/// ↑↓ navigate, ⏎ confirm, esc close, ⌘C/⌘R/⌘I/⌘↩/⌘E on the result.
public struct PanelView: View {
    @Bindable private var vm: PanelViewModel
    @FocusState private var promptFocused: Bool

    public init(vm: PanelViewModel) { self.vm = vm }

    public var body: some View {
        ZStack {
            content
            shortcuts
        }
        .frame(width: 500)
        .leafPanelChrome()
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

    // MARK: Header

    private func header(_ title: String, spinning: Bool = false) -> some View {
        HStack(spacing: 8) {
            SparkMark()
                .fill(Leaf.markGradient)
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 1.6).repeatForever(autoreverses: false) : .default, value: spinning)
            Text(title).font(Leaf.font(16, .semibold))
            Spacer()
            ProviderChip(name: vm.providerName, isMock: vm.isMockProvider)
        }
        .overlay(WindowDragArea()) // the header is the drag handle
    }

    // MARK: Screens

    private var actionsScreen: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("APILA")
            contextCard
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(vm.items.enumerated()), id: \.element.id) { index, item in
                    if case .screenshotText = item {
                        sectionLabel("Screenshot")
                    }
                    row(item, selected: index == vm.selectedIndex)
                        .onHover { if $0 { vm.selectedIndex = index } }
                        .onTapGesture { vm.selectedIndex = index; vm.confirm() }
                }
            }
            HintBar(items: [("↑↓", "navigate"), ("↩", "select"), ("esc", "close")])
                .padding(.top, 2)
        }
        .padding(14)
    }

    private var contextCard: some View {
        HStack(alignment: .top, spacing: 8) {
            if let preview = vm.contextPreview {
                let fromClipboard = preview.source == "Clipboard"
                Text(preview.source)
                    .font(Leaf.font(11, .semibold))
                    .foregroundStyle(fromClipboard ? Leaf.amber : Leaf.ink)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((fromClipboard ? Leaf.amber : Leaf.ink).opacity(0.15), in: Capsule())
                Text(preview.text)
                    .font(Leaf.font(14))
                    .lineLimit(2)
            } else {
                Text("No text captured — select text or copy it first. Screenshots work anyway.")
                    .font(Leaf.font(14))
                    .foregroundStyle(Leaf.amber)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Leaf.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Leaf.font(10, .bold))
            .tracking(0.8)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func row(_ item: PanelViewModel.Item, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(selected ? AnyShapeStyle(Leaf.accent) : AnyShapeStyle(Color.clear))
                .frame(width: 3, height: 16)
            Text(item.title)
                .font(Leaf.font(15, selected ? .semibold : .regular))
            Spacer()
            if selected { Keycap(key: "↩") }
        }
        .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 7)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Leaf.selection)
            }
        }
        .contentShape(Rectangle())
    }

    private var customPromptScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(promptTitle)
            TextField(promptPlaceholder, text: $vm.customPromptText)
                .textFieldStyle(.plain)
                .font(Leaf.font(15))
                .padding(11)
                .background(Leaf.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(promptFocused ? AnyShapeStyle(Leaf.markGradient) : AnyShapeStyle(.primary.opacity(0.10)), lineWidth: promptFocused ? 1.5 : 1)
                }
                .focused($promptFocused)
                .onSubmit { vm.confirm() }
            HintBar(items: [("↩", "run"), ("esc", vm.isRefining ? "back" : "cancel")])
        }
        .padding(14)
        .onAppear { promptFocused = true }
    }

    private var generatingScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("Thinking…", spinning: true)
            FittingScrollText(text: vm.output, maxHeight: 220)
            HintBar(items: [("esc", "stop")])
        }
        .padding(14)
    }

    private var resultScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(vm.errorText == nil ? "Result" : "Something went wrong")
            FittingScrollText(text: vm.errorText ?? vm.output, color: vm.errorText == nil ? .primary : .red)
                .padding(12)
                .background(Leaf.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 6) {
                Button("Copy") { Task { await vm.copyResult() } }
                    .buttonStyle(LeafButtonStyle(prominent: true))
                    .keyboardShortcut("c", modifiers: .command)
                Button("Replace") { Task { await vm.replaceSelection() } }
                    .buttonStyle(LeafButtonStyle())
                    .keyboardShortcut("r", modifiers: .command)
                Button("Insert Below") { Task { await vm.insertBelow() } }
                    .buttonStyle(LeafButtonStyle())
                    .keyboardShortcut("i", modifiers: .command)
                Spacer()
                Button("Retry") { vm.retry() }
                    .buttonStyle(LeafButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Refine") { vm.refine() }
                    .buttonStyle(LeafButtonStyle())
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(vm.errorText != nil)
                    .opacity(vm.errorText != nil ? 0.4 : 1)
                Button("Close") { vm.close() }
                    .buttonStyle(LeafButtonStyle())
            }

            if let notice = vm.noticeText {
                Text(notice).font(Leaf.font(12)).foregroundStyle(Leaf.amber)
            }
            HintBar(items: [("⌘C", "copy"), ("⌘R", "replace"), ("⌘↩", "retry"), ("⌘E", "refine"), ("esc", "close")])
        }
        .padding(14)
    }

    // MARK: Hidden keyboard handlers (active while the panel is key)

    @ViewBuilder
    private var shortcuts: some View {
        VStack {
            Button("") { vm.cancel() }.keyboardShortcut(.cancelAction)
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

    private var promptTitle: String {
        switch vm.promptMode {
        case .custom: "Custom Prompt"
        case .refine: "Refine Result"
        case .screenshot: "Ask about Screenshot"
        }
    }

    private var promptPlaceholder: String {
        switch vm.promptMode {
        case .custom: "Describe what to do with the selection…"
        case .refine: "How should the result change? (shorter, more formal…)"
        case .screenshot: "What do you want to know about it?"
        }
    }
}
