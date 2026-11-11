import SwiftUI

/// The panel's snippets tab.
extension ClipboardPanelView {
    // MARK: Snippets

    /// Folders on the left, like the snippets editor.
    var folderList: some View {
        let searching = !model.query.isEmpty
        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                folderRow(nil, name: String(localized: "All Snippets"), color: nil, count: model.snippets.snippets.count, dimmed: searching)
                ForEach(model.snippets.folders) { f in
                    folderRow(f.id, name: f.name, color: SnippetFolder.colors[f.color % SnippetFolder.colors.count],
                              count: model.snippets.snippets.filter { $0.folder == f.id }.count, dimmed: searching)
                }
                Spacer(minLength: 8)
                Text(searching ? "Searching all folders" : "← → folders").font(Leaf.font(11)).opacity(0.45).padding(.horizontal, 8)
            }
            .padding(8)
        }
    }

    func folderRow(_ id: UUID?, name: String, color: NSColor?, count: Int, dimmed: Bool) -> some View {
        let on = !dimmed && model.snippetFolder == id
        return HStack(spacing: 8) {
            if let color { Circle().fill(Color(nsColor: color)).frame(width: 10, height: 10) }
            else { Image(systemName: "tray.full").font(.system(size: 11)).frame(width: 10) }
            Text(name).font(Leaf.font(13, .medium)).lineLimit(1)
            Spacer(minLength: 4)
            Text("\(count)").font(Leaf.font(11)).opacity(0.45).monospacedDigit()
        }
        .foregroundStyle(on ? Leaf.ink : Color.primary)
        .opacity(dimmed ? 0.5 : 1)
        .padding(.horizontal, 8).frame(height: 30)
        .background { if on { tile(true) } }
        .contentShape(Rectangle())
        .onTapGesture { model.query = ""; model.snippetFolder = id }
        .onDrop(of: [.item], isTargeted: nil) { _ in dropDragged(into: id) }
    }

    var snippetList: some View {
        let results = model.snippetResults
        return ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if results.isEmpty {
                        VStack(spacing: 10) {
                            Text(model.snippets.snippets.isEmpty ? "No snippets yet" : "Nothing found").font(Leaf.font(13)).opacity(0.5)
                            if model.snippets.snippets.isEmpty {
                                Button("Create a snippet", action: editSnippets).buttonStyle(LeafButtonStyle(prominent: true))
                            }
                        }
                        .padding(.top, 40)
                    }
                    ForEach(Array(results.enumerated()), id: \.element.id) { i, snippet in
                        snippetRow(snippet, index: i)
                            .id(snippet.id)
                            .onHover { if $0 { model.selected = i } }
                            .onTapGesture { pickSnippet(snippet, .paste) } // one click pastes
                    }
                }
                .padding(8)
            }
            .onChange(of: model.selected) { _, i in
                if results.indices.contains(i) { scroller.scrollTo(results[i].id) }
            }
        }
    }

    func snippetRow(_ snippet: Snippet, index: Int) -> some View {
        let on = index == model.selected
        return HStack(spacing: 10) {
            Text(index < 9 ? "\(index + 1)" : "")
                .font(Leaf.font(11, .semibold)).monospacedDigit()
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(on ? Leaf.fresh.opacity(0.45) : Color.primary.opacity(index < 9 ? 0.06 : 0)))
                .foregroundStyle(on ? Leaf.ink : Color.primary.opacity(0.55))
            Circle().fill(Color(nsColor: model.snippets.folder(snippet.folder).map { SnippetFolder.colors[$0.color % SnippetFolder.colors.count] } ?? .tertiaryLabelColor))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(snippet.title).font(Leaf.font(13, .medium)).lineLimit(1)
                Text(snippet.text.replacingOccurrences(of: "\n", with: " ")).font(Leaf.font(11)).opacity(0.5).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let count = snippet.images?.count, count > 0 {
                Label("\(count)", systemImage: "photo").font(Leaf.font(11, .medium)).opacity(0.55)
            }
            if !snippet.abbreviation.isEmpty { Keycap(key: snippet.abbreviation) }
        }
        .padding(.horizontal, 8).frame(height: 42)
        .background { if on { tile(true) } }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    var snippetPreview: some View {
        if let snippet = model.asking {
            VStack(alignment: .leading, spacing: 10) {
                Text(snippet.title).font(Leaf.font(14, .semibold))
                ForEach(Array(SnippetText.questions(in: snippet.text).enumerated()), id: \.element) { i, question in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(question).font(Leaf.font(12, .medium)).opacity(0.7)
                        TextField("", text: Binding(get: { model.answers[question] ?? "" }, set: { model.answers[question] = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .focused($answering, equals: i)
                    }
                }
                Text(SnippetText.expand(snippet.text, answers: model.answers).text)
                    .font(Leaf.font(12)).opacity(0.6).lineLimit(6)
                Spacer(minLength: 0)
                Text("↩ pastes · esc goes back").font(Leaf.font(11)).opacity(0.5)
            }
            .padding(14)
            .onAppear { answering = 0 }
        } else if let snippet = model.currentSnippet {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView {
                    Text(SnippetText.expand(snippet.text, clipboard: "📋").text)
                        .font(Leaf.font(13)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SnippetImages(urls: model.snippets.imageURLs(snippet))
                }
                Spacer(minLength: 0)
                Text([model.snippets.folder(snippet.folder)?.name, snippet.abbreviation.isEmpty ? nil : snippet.abbreviation]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(Leaf.font(11)).opacity(0.5)
            }
            .padding(14)
        } else {
            Color.clear
        }
    }
}
