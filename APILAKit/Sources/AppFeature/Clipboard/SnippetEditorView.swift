import SwiftUI

/// The snippets editor, in the screenshot window's look: folders, the
/// snippets in the chosen one, and the selected snippet with a live preview.
struct SnippetEditorView: View {
    @Bindable var store: SnippetStore
    var close: () -> Void = {}
    /// nil = all snippets.
    @State private var folder: UUID?
    @State private var selected: UUID?
    @State private var query = ""

    private var shown: [Snippet] {
        store.search(query).filter { folder == nil || $0.folder == folder }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(alignment: .top, spacing: 12) {
                folders.frame(width: 190).background(card)
                list.frame(width: 240).background(card)
                editor.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(card)
            }
            HStack(spacing: 6) {
                Button { newSnippet() } label: {
                    HStack(spacing: 5) {
                        Text("New Snippet")
                        Text(verbatim: "⌘N").font(Leaf.font(10.5, .semibold)).opacity(0.5)
                    }
                }
                .buttonStyle(LeafButtonStyle(prominent: true))
                .keyboardShortcut("n", modifiers: .command)
                Button("New Folder") { newFolder() }.buttonStyle(LeafButtonStyle())
                Spacer()
                Button(action: close) {
                    HStack(spacing: 5) {
                        Text("Close")
                        Text(verbatim: "esc").font(Leaf.font(10.5, .semibold)).opacity(0.5)
                    }
                }
                .buttonStyle(LeafButtonStyle())
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(minWidth: 920, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .leafPanelChrome()
        .overlay(alignment: .bottomTrailing) { WindowResizeGrip().frame(width: 12, height: 12).padding(2) }
        .overlay(WindowEdgeResizer())
        .onAppear { selected = selected ?? shown.first?.id }
    }

    private var card: some View { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.035)) }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                BrandLogo()
                Text("Snippets").font(Leaf.font(15, .semibold))
            }
            .fixedSize()
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold)).foregroundStyle(Leaf.ink)
                TextField("Search", text: $query).textFieldStyle(.plain).font(Leaf.font(13))
            }
            .padding(.horizontal, 10)
            .frame(width: 240, height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.primary.opacity(0.04)))
        }
        .overlay(WindowDragArea().allowsHitTesting(false))
    }

    // MARK: Folders

    private var folders: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                folderRow(nil, name: String(localized: "All Snippets"), color: nil, count: store.snippets.count)
                ForEach($store.folders) { $f in
                    folderRow(f.id, name: f.name, color: SnippetFolder.colors[f.color % SnippetFolder.colors.count],
                              count: store.snippets.filter { $0.folder == f.id }.count, rename: $f.name) {
                        f.color = (f.color + 1) % SnippetFolder.colors.count
                    }
                }
            }
            .padding(8)
        }
    }

    private func folderRow(_ id: UUID?, name: String, color: NSColor?, count: Int,
                           rename: Binding<String>? = nil, recolor: (() -> Void)? = nil) -> some View {
        let on = folder == id
        return HStack(spacing: 8) {
            if let color {
                Button { recolor?() } label: { Circle().fill(Color(nsColor: color)).frame(width: 10, height: 10) }
                    .buttonStyle(.plain)
                    .instantTip(String(localized: "Change colour"))
            } else {
                Image(systemName: "tray.full").font(.system(size: 11)).frame(width: 10)
            }
            if on, let rename {
                TextField("", text: rename).textFieldStyle(.plain).font(Leaf.font(13, .medium))
            } else {
                Text(name).font(Leaf.font(13, .medium)).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(count)").font(Leaf.font(11)).opacity(0.45).monospacedDigit()
            if on, let id {
                Button { deleteFolder(id) } label: { Image(systemName: "trash").font(.system(size: 11)) }
                    .buttonStyle(.plain).opacity(0.6)
                    .instantTip(String(localized: "Delete the folder (its snippets stay)"))
            }
        }
        .foregroundStyle(on ? Leaf.ink : Color.primary)
        .padding(.horizontal, 8).frame(height: 30)
        .background { if on { tile } }
        .contentShape(Rectangle())
        .onTapGesture { folder = id; selected = shown.first?.id }
    }

    private var tile: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Leaf.selection)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Leaf.markGradient, lineWidth: 1.2))
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if shown.isEmpty {
                    Text(query.isEmpty ? "No snippets here yet" : "Nothing found").font(Leaf.font(12)).opacity(0.5).padding(.top, 30)
                        .frame(maxWidth: .infinity)
                }
                ForEach(shown) { snippet in
                    let on = selected == snippet.id
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(snippet.title.isEmpty ? String(localized: "Untitled") : snippet.title).font(Leaf.font(13, .medium)).lineLimit(1)
                            Spacer(minLength: 4)
                            if !snippet.abbreviation.isEmpty { Keycap(key: snippet.abbreviation) }
                        }
                        Text(snippet.text.replacingOccurrences(of: "\n", with: " ")).font(Leaf.font(11)).opacity(0.5).lineLimit(1)
                    }
                    .foregroundStyle(on ? Leaf.ink : Color.primary)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background { if on { tile } }
                    .contentShape(Rectangle())
                    .onTapGesture { selected = snippet.id }
                }
            }
            .padding(8)
        }
    }

    // MARK: Editor

    @ViewBuilder
    private var editor: some View {
        if let i = store.snippets.firstIndex(where: { $0.id == selected }) {
            let snippet = $store.snippets[i]
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom, spacing: 10) {
                    field("Name") { TextField("", text: snippet.title).textFieldStyle(.roundedBorder) }
                    field("Abbreviation") {
                        TextField("", text: snippet.abbreviation, prompt: Text(verbatim: ";addr")).textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, design: .monospaced))
                    }
                    .frame(width: 130)
                    field("Folder") {
                        Picker("", selection: snippet.folder) {
                            Text("None").tag(UUID?.none)
                            ForEach(store.folders) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                        .labelsHidden()
                    }
                    .frame(width: 150)
                }
                if let clash = abbreviationClash(store.snippets[i]) {
                    Text("“\(clash)” already uses this abbreviation").font(Leaf.font(11)).foregroundStyle(.orange)
                }
                field("Text") {
                    TextEditor(text: snippet.text)
                        .font(Leaf.font(13))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.12)))
                        .frame(minHeight: 140)
                }
                HStack(spacing: 6) {
                    Text("Insert:").font(Leaf.font(11, .medium)).opacity(0.6)
                    ForEach(["{date}", "{time}", "{clipboard}", "{cursor}", "{?Name}"], id: \.self) { variable in
                        Button { store.snippets[i].text += variable } label: {
                            Text(verbatim: variable).font(.system(size: 11, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Leaf.fresh.opacity(0.3)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("{?Name} asks before pasting; {cursor} is where the caret ends up.").font(Leaf.font(11)).opacity(0.5)
                field("Pastes as") {
                    Text(SnippetText.expand(store.snippets[i].text, clipboard: String(localized: "(clipboard)")).text)
                        .font(Leaf.font(12)).opacity(0.75).lineLimit(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Button("Delete Snippet") { deleteSnippet(store.snippets[i].id) }.buttonStyle(LeafButtonStyle())
                }
            }
            .padding(14)
        } else {
            VStack(spacing: 10) {
                Text("Pick a snippet or create one").font(Leaf.font(13)).opacity(0.5)
                Button("New Snippet") { newSnippet() }.buttonStyle(LeafButtonStyle(prominent: true))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func field<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Leaf.font(11, .medium)).opacity(0.6)
            content()
        }
    }

    // MARK: Actions

    private func abbreviationClash(_ snippet: Snippet) -> String? {
        guard !snippet.abbreviation.isEmpty else { return nil }
        return store.snippets.first { $0.id != snippet.id && $0.abbreviation == snippet.abbreviation }?.title
    }

    private func newSnippet() {
        let snippet = Snippet(title: String(localized: "New snippet"), text: "", folder: folder)
        store.snippets.insert(snippet, at: 0)
        query = ""
        selected = snippet.id
    }

    private func newFolder() {
        let new = SnippetFolder(name: String(localized: "New folder"), color: store.folders.count % SnippetFolder.colors.count)
        store.folders.append(new)
        folder = new.id
        selected = nil
    }

    private func deleteFolder(_ id: UUID) {
        for i in store.snippets.indices where store.snippets[i].folder == id { store.snippets[i].folder = nil }
        store.folders.removeAll { $0.id == id }
        folder = nil
    }

    private func deleteSnippet(_ id: UUID) {
        store.snippets.removeAll { $0.id == id }
        selected = shown.first?.id
    }
}
