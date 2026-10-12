import SwiftUI

/// The ⇧⌘V panel (history and snippets), in the screenshot window's look: name, search and type
/// tiles on top; the list (1–9 on the first rows) and a preview on canvas
/// cards; actions with their keys at the bottom.
struct ClipboardPanelView: View {
    @Bindable var model: ClipboardPanelModel
    let pick: (ClipItem, ClipboardPanelController.Mode) -> Void
    var pickSnippet: (Snippet, ClipboardPanelController.Mode) -> Void = { _, _ in }
    var editSnippets: () -> Void = {}
    let close: () -> Void
    @FocusState private var searching: Bool
    @FocusState private var answering: Int?

    var body: some View {
        let results = model.results
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(spacing: 12) {
                if model.showsSnippets {
                    folderList.frame(width: 230).background(card)
                    Group { if model.asking != nil { snippetPreview } else { snippetList } }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(card)
                } else {
                    list(results).frame(width: 380).background(card)
                    preview.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(card)
                }
            }
            actionRow
        }
        .padding(14)
        .frame(width: 780, height: 500)
        .leafPanelChrome()
        .onAppear { searching = true }
    }

    /// The canvas look of the screenshot window.
    private var card: some View { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.035)) }

    /// Like the screenshot window: name on the left, then the search and the
    /// type filters as tool tiles.
    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                BrandLogo()
                Text("Clipboard").font(Leaf.font(15, .semibold))
            }
            .fixedSize()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundStyle(Leaf.ink)
                TextField("Search the clipboard", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(Leaf.font(14))
                    .focused($searching)
                if model.history.isPaused {
                    Text("Paused").font(Leaf.font(11, .semibold)).foregroundStyle(Leaf.ink)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.primary.opacity(0.04)))
            HStack(spacing: 4) {
                ForEach(ClipboardPanelModel.kinds, id: \.self) { kind in
                    tileButton(Self.symbol(kind), String(localized: Self.titleString(kind)), on: !model.showsSnippets && model.kind == kind) {
                        model.showsSnippets = false
                        model.kind = kind
                    }
                }
                Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 22).padding(.horizontal, 4)
                tileButton("text.badge.star", String(localized: "Snippets") + "  Tab", on: model.showsSnippets) { model.showsSnippets = true }
            }
        }
        .overlay(WindowDragArea().allowsHitTesting(false))
        .zIndex(1) // tips over the list
    }

    private func tileButton(_ symbol: String, _ tip: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(on ? Leaf.ink : Color.primary.opacity(0.8))
                .frame(width: 38, height: 36)
                .background(tile(on))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .instantTip(tip)
    }

    /// The editor's tool tile: green when on.
    private func tile(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(on ? AnyShapeStyle(Leaf.selection) : AnyShapeStyle(.primary.opacity(0.04)))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(on ? AnyShapeStyle(Leaf.markGradient) : AnyShapeStyle(.clear), lineWidth: 1.2)
            }
    }

    /// The screenshot window's action row: buttons with their keys on them.
    private var actionRow: some View {
        ViewThatFits(in: .horizontal) { actions(keys: true); actions(keys: false) }
    }

    @ViewBuilder
    private func actions(keys: Bool) -> some View {
        if model.showsSnippets { snippetActions(keys: keys) } else { historyActions(keys: keys) }
    }

    private func snippetActions(keys: Bool) -> some View {
        let snippet = model.asking ?? model.currentSnippet
        return HStack(spacing: 6) {
            Button { if let snippet { pickSnippet(snippet, .paste) } } label: { keyed("Paste", "↩", show: keys) }
                .buttonStyle(LeafButtonStyle(prominent: true)).disabled(snippet == nil)
            Button { if let snippet { pickSnippet(snippet, .copy) } } label: { keyed("Copy", "⌘↩", show: keys) }
                .buttonStyle(LeafButtonStyle()).disabled(snippet == nil)
            Button(action: editSnippets) { keyed("Edit Snippets…", "", show: false) }
                .buttonStyle(LeafButtonStyle())
            Spacer(minLength: 6)
            Button(action: close) { keyed("Close", "esc", show: keys) }
                .buttonStyle(LeafButtonStyle())
        }
    }

    private func historyActions(keys: Bool) -> some View {
        let item = model.current
        return HStack(spacing: 6) {
            Button { if let item { pick(item, .paste) } } label: { keyed("Paste", "↩", show: keys) }
                .buttonStyle(LeafButtonStyle(prominent: true)).disabled(item == nil)
            Button { if let item { pick(item, .plain) } } label: { keyed("Plain text", "⌥↩", show: keys) }
                .buttonStyle(LeafButtonStyle()).disabled(item == nil)
            Button { if let item { pick(item, .copy) } } label: { keyed("Copy", "⌘↩", show: keys) }
                .buttonStyle(LeafButtonStyle()).disabled(item == nil)
            Button { if let item { model.history.togglePin(item.id) } } label: { keyed(item?.pinned == true ? "Unpin" : "Pin", "⌘P", show: keys) }
                .buttonStyle(LeafButtonStyle()).disabled(item == nil)
            Spacer(minLength: 6)
            Button { if let item { model.history.remove(item.id); model.move(0) } } label: { keyed("Delete", "⌘⌫", show: keys) }
                .buttonStyle(LeafButtonStyle()).disabled(item == nil)
            Button(action: close) { keyed("Close", "esc", show: keys) }
                .buttonStyle(LeafButtonStyle())
        }
    }

    private func keyed(_ title: String, _ key: String, show: Bool) -> some View {
        HStack(spacing: 5) {
            Text(LocalizedStringKey(title))
            if show { Text(key)
                .font(Leaf.font(10.5, .semibold))
                .opacity(0.5)
                .padding(.horizontal, 3).padding(.vertical, 1)
                .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4)) }
        }
    }

    // MARK: List

    private func list(_ results: [ClipItem]) -> some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if results.isEmpty {
                        Text(model.history.items.isEmpty ? "Copy something — it shows up here" : "Nothing found")
                            .font(Leaf.font(13)).opacity(0.5).padding(.top, 40)
                    }
                    ForEach(Array(results.enumerated()), id: \.element.id) { i, item in
                        row(item, index: i)
                            .id(item.id)
                            .onTapGesture(count: 2) { pick(item, .paste) }
                            .onTapGesture { model.selected = i }
                    }
                }
                .padding(8)
            }
            .onChange(of: model.selected) { _, i in
                if results.indices.contains(i) { scroller.scrollTo(results[i].id) }
            }
        }
    }

    private func row(_ item: ClipItem, index: Int) -> some View {
        let on = index == model.selected
        return HStack(spacing: 10) {
            Text(index < 9 ? "\(index + 1)" : "")
                .font(Leaf.font(11, .semibold)).monospacedDigit()
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(on ? Leaf.fresh.opacity(0.45) : Color.primary.opacity(index < 9 ? 0.06 : 0)))
                .foregroundStyle(on ? Leaf.ink : Color.primary.opacity(0.55))
            ClipIcon(item: item, history: model.history)
            Text(Self.line(item)).font(Leaf.font(13)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            if item.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Leaf.ink) }
            Text(Self.meta(item)).font(Leaf.font(11)).opacity(0.45).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 8).frame(height: 32)
        .background { if on { tile(true) } }
        .contentShape(Rectangle())
    }

    // MARK: Snippets

    /// Folders on the left, like the snippets editor.
    private var folderList: some View {
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

    private func folderRow(_ id: UUID?, name: String, color: NSColor?, count: Int, dimmed: Bool) -> some View {
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
    }

    private var snippetList: some View {
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
                            .onTapGesture(count: 2) { pickSnippet(snippet, .paste) }
                            .onTapGesture { model.selected = i }
                    }
                }
                .padding(8)
            }
            .onChange(of: model.selected) { _, i in
                if results.indices.contains(i) { scroller.scrollTo(results[i].id) }
            }
        }
    }

    private func snippetRow(_ snippet: Snippet, index: Int) -> some View {
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
            if !snippet.abbreviation.isEmpty { Keycap(key: snippet.abbreviation) }
        }
        .padding(.horizontal, 8).frame(height: 42)
        .background { if on { tile(true) } }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var snippetPreview: some View {
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

    // MARK: Preview

    @ViewBuilder
    private var preview: some View {
        if let item = model.current {
            VStack(alignment: .leading, spacing: 10) {
                switch item.kind {
                case .image:
                    if let image = model.history.image(item) {
                        Image(nsImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .frame(maxHeight: 220)
                    }
                    if let text = item.imageText, !text.isEmpty {
                        Text(highlighted(String(text.prefix(400)))).font(Leaf.font(11)).opacity(0.7).lineLimit(5)
                    }
                case .color:
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Self.color(item.text) ?? .clear)
                        .frame(height: 90)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.1)))
                    Text(item.text).font(.system(size: 15, weight: .semibold, design: .monospaced))
                case .file:
                    ForEach(item.fileURLs, id: \.self) { url in
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(url.lastPathComponent).font(Leaf.font(13, .medium))
                                Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath).font(Leaf.font(11)).opacity(0.5)
                            }
                        }
                    }
                default:
                    ScrollView {
                        Text(highlighted(String(item.text.prefix(4000))))
                            .font(item.kind == .link ? Leaf.font(13, .medium) : Leaf.font(13))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Spacer(minLength: 0)
                Text(Self.details(item)).font(Leaf.font(11)).opacity(0.5)
            }
            .padding(14)
        } else {
            Color.clear
        }
    }

    /// The search words marked in the text.
    private func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        for word in model.query.lowercased().split(separator: " ") where !word.isEmpty {
            var from = result.startIndex
            while let range = result[from...].range(of: String(word), options: .caseInsensitive) {
                result[range].backgroundColor = Leaf.fresh.opacity(0.45)
                from = range.upperBound
            }
        }
        return result
    }

    // MARK: Texts

    static func titleString(_ kind: ClipItem.Kind?) -> String.LocalizationValue {
        switch kind {
        case nil: "All"
        case .text?: "Text"
        case .link?: "Links"
        case .image?: "Images"
        case .color?: "Colors"
        case .file?: "Files"
        }
    }

    static func symbol(_ kind: ClipItem.Kind?) -> String {
        switch kind {
        case nil: "square.grid.2x2"
        case .text?: "text.alignleft"
        case .link?: "link"
        case .image?: "photo"
        case .color?: "paintpalette"
        case .file?: "doc"
        }
    }

    /// The row's text: the first non-empty line.
    static func line(_ item: ClipItem) -> String {
        switch item.kind {
        case .image:
            let size = item.imageSize.map { "\(Int($0.width))×\(Int($0.height))" } ?? ""
            let words = item.imageText?.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return [String(localized: "Image"), size, words.isEmpty ? "" : "«\(words.prefix(40))»"].filter { !$0.isEmpty }.joined(separator: " · ")
        case .file: return item.fileURLs.map(\.lastPathComponent).joined(separator: ", ")
        default: return item.text.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? item.text
        }
    }

    static func meta(_ item: ClipItem) -> String {
        let ago = RelativeDateTimeFormatter()
        ago.unitsStyle = .short
        let when = Date().timeIntervalSince(item.date) < 60 ? String(localized: "now") : ago.localizedString(for: item.date, relativeTo: Date())
        return [item.appName, when].compactMap { $0 }.joined(separator: " · ")
    }

    static func details(_ item: ClipItem) -> String {
        let when = item.date.formatted(date: Calendar.current.isDateInToday(item.date) ? .omitted : .abbreviated, time: .shortened)
        let size = item.kind == .text || item.kind == .link ? String(localized: "\(item.text.count) characters") : nil
        return [item.appName, when, size].compactMap { $0 }.joined(separator: " · ")
    }

    static func color(_ hex: String) -> Color? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard let value = UInt32(digits.prefix(6), radix: 16) else { return nil }
        return Color(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

/// A row's small picture: thumbnail, colour swatch, app/file/link icon.
private struct ClipIcon: View {
    let item: ClipItem
    let history: ClipboardHistory
    @State private var thumb: NSImage?

    var body: some View {
        Group {
            switch item.kind {
            case .image:
                if let thumb { Image(nsImage: thumb).resizable().scaledToFill() } else { Color.primary.opacity(0.08) }
            case .color:
                ClipboardPanelView.color(item.text) ?? .clear
            case .link: Image(systemName: "link").foregroundStyle(Leaf.ink)
            case .file: Image(systemName: "doc").foregroundStyle(.secondary)
            case .text: Image(systemName: "text.alignleft").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .frame(width: item.kind == .image ? 34 : 18, height: item.kind == .image ? 22 : 18)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .task(id: item.id) {
            guard item.kind == .image else { return }
            let url = history.imageURL(item)
            if let cg = await Task.detached(operation: { BatchWatermarkView.thumbnail(url, maxPixels: 80) }).value {
                thumb = NSImage(cgImage: cg, size: .zero)
            }
        }
    }
}
