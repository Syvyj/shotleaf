import SwiftUI

/// The ⇧⌘V panel (history and snippets), in the screenshot window's look: name, search and type
/// tiles on top; the list (⌘1–⌘9 on the first rows) and a preview on canvas
/// cards; actions with their keys at the bottom.
struct ClipboardPanelView: View {
    @Bindable var model: ClipboardPanelModel
    let pick: (ClipItem, ClipboardPanelController.Mode) -> Void
    var pickSnippet: (Snippet, ClipboardPanelController.Mode) -> Void = { _, _ in }
    var editSnippets: () -> Void = {}
    var pickTogether: ([ClipItem]) -> Void = { _ in }
    var pickQueue: ([ClipItem]) -> Void = { _ in }
    var runAction: (ClipAction) -> Void = { _ in }
    var saveSnippet: ([ClipItem], UUID?) -> Void = { _, _ in }
    let close: () -> Void
    @FocusState var searching: Bool
    @FocusState var answering: Int?

    var body: some View {
        let results = model.results
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(spacing: 12) {
                if model.showsSnippets {
                    folderList.frame(width: 230).background(card)
                    Group { if model.asking != nil { snippetPreview } else { snippetList } }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(card)
                        .onDrop(of: [.item], isTargeted: nil) { _ in dropDragged(into: model.snippetFolder) }
                } else {
                    list(results).frame(width: 380).background(card)
                    Group { if model.actionsShown { actionList } else { preview } }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(card)
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
    var card: some View { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.035)) }

    /// Like the screenshot window: name on the left, then the search and the
    /// type filters as tool tiles.
    var header: some View {
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
                tileButton("text.badge.star", String(localized: "Snippets") + "  Tab", on: model.showsSnippets, trailing: true) { model.showsSnippets = true }
                    // An entry dragged here opens the snippets, to drop it on a folder.
                    .onDrop(of: [.item], isTargeted: Binding(get: { false }, set: { if $0, model.dragged != nil { model.showsSnippets = true } })) { _ in
                        dropDragged(into: model.snippetFolder)
                    }
            }
        }
        .overlay(WindowDragArea().allowsHitTesting(false))
        .zIndex(1) // tips over the list
    }

    func tileButton(_ symbol: String, _ tip: String, on: Bool, trailing: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(on ? Leaf.ink : Color.primary.opacity(0.8))
                .frame(width: 38, height: 36)
                .background(tile(on))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .instantTip(tip, trailing: trailing)
    }

    /// The editor's tool tile: green when on.
    func tile(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(on ? AnyShapeStyle(Leaf.selection) : AnyShapeStyle(.primary.opacity(0.04)))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(on ? AnyShapeStyle(Leaf.markGradient) : AnyShapeStyle(.clear), lineWidth: 1.2)
            }
    }

    /// The screenshot window's action row: buttons with their keys on them.
    var actionRow: some View {
        ViewThatFits(in: .horizontal) { actions(keys: true); actions(keys: false) }
    }

    @ViewBuilder
    func actions(keys: Bool) -> some View {
        if model.showsSnippets { snippetActions(keys: keys) } else { historyActions(keys: keys) }
    }

    func snippetActions(keys: Bool) -> some View {
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

    @ViewBuilder
    func historyActions(keys: Bool) -> some View {
        if model.marked.count > 1 { markedActions(keys: keys) } else { singleActions(keys: keys) }
    }

    /// Several entries picked: paste them as one text, or one by one.
    func markedActions(keys: Bool) -> some View {
        HStack(spacing: 6) {
            Button { pickTogether(model.markedItems) } label: { keyed("Paste Together", "↩", show: keys) }
                .buttonStyle(LeafButtonStyle(prominent: true))
            Button { pickQueue(model.markedItems) } label: { keyed("Paste One by One", "⌘↩", show: keys) }
                .buttonStyle(LeafButtonStyle())
            Text("\(model.marked.count) picked").font(Leaf.font(12, .medium)).opacity(0.6).padding(.leading, 4)
            Spacer(minLength: 6)
            Button { model.marked = [] } label: { keyed("Clear Selection", "esc", show: keys) }
                .buttonStyle(LeafButtonStyle())
        }
    }

    func singleActions(keys: Bool) -> some View {
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
            Button { model.actionsShown.toggle() } label: { keyed("Actions", "⌘K", show: keys) }
                .buttonStyle(LeafButtonStyle(prominent: model.actionsShown)).disabled(model.actions.isEmpty)
            Spacer(minLength: 6)
            Button { if let item { model.history.remove(item.id); model.move(0) } } label: { keyed("Delete", "⌘⌫", show: keys) }
                .buttonStyle(LeafButtonStyle()).disabled(item == nil)
            Button(action: close) { keyed("Close", "esc", show: keys) }
                .buttonStyle(LeafButtonStyle())
        }
    }

    func keyed(_ title: String, _ key: String, show: Bool) -> some View {
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

    func list(_ results: [ClipItem]) -> some View {
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
                            .onHover { if $0 { model.selected = i } } // the preview follows the mouse
                            .onTapGesture {
                                // One click pastes; ⌘-click picks several instead.
                                if NSEvent.modifierFlags.contains(.command) { model.toggleMark(item.id); model.selected = i }
                                else { pick(item, .paste) }
                            }
                            .onDrag { model.dragged = item; return dragProvider(item) }
                            .contextMenu { menu(item, index: i) }
                    }
                }
                .padding(8)
            }
            .onChange(of: model.selected) { _, i in
                if results.indices.contains(i) { scroller.scrollTo(results[i].id) }
            }
        }
    }

    func row(_ item: ClipItem, index: Int) -> some View {
        let on = index == model.selected
        return HStack(spacing: 10) {
            Text(index < 9 ? "⌘\(index + 1)" : "")
                .font(Leaf.font(11, .semibold)).monospacedDigit()
                .frame(width: 28, height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(on ? Leaf.fresh.opacity(0.45) : Color.primary.opacity(index < 9 ? 0.06 : 0)))
                .foregroundStyle(on ? Leaf.ink : Color.primary.opacity(0.55))
            if let order = model.marked.firstIndex(of: item.id) {
                Text("\(order + 1)").font(Leaf.font(10, .bold)).foregroundStyle(.white)
                    .frame(width: 18, height: 18).background(Circle().fill(Leaf.leaf))
            }
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

    /// Right click: what the action row does, for this entry.
    @ViewBuilder
    func menu(_ item: ClipItem, index: Int) -> some View {
        Button("Paste") { pick(item, .paste) }
        Button("Plain text") { pick(item, .plain) }
        Button("Copy") { pick(item, .copy) }
        Divider()
        Button(item.pinned ? "Unpin" : "Pin") { model.history.togglePin(item.id) }
        Button("Save as snippet") { saveSnippet(model.entries(with: item), model.snippetFolder) }
        if item.kind != .image, item.kind != .file { Button("Actions") { model.selected = index; model.actionsShown = true } }
        Divider()
        Button("Delete") { model.history.remove(item.id); model.move(0) }
    }

    /// The entry as other apps take it: the picture, the files, or the text.
    func dragProvider(_ item: ClipItem) -> NSItemProvider {
        switch item.kind {
        case .image: NSItemProvider(contentsOf: model.history.imageURL(item)) ?? NSItemProvider()
        case .file: item.fileURLs.first.flatMap(NSItemProvider.init(contentsOf:)) ?? NSItemProvider()
        default: NSItemProvider(object: item.text as NSString)
        }
    }

    /// Drops the entry dragged from the list (and the others picked with it) into a folder.
    func dropDragged(into folder: UUID?) -> Bool {
        guard let item = model.dragged else { return false }
        model.dragged = nil
        saveSnippet(model.entries(with: item), folder)
        model.snippetFolder = folder
        return true
    }

    // MARK: Actions (⌘K)

    var actionList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Paste it…").font(Leaf.font(11, .semibold)).opacity(0.5).padding(.horizontal, 8).padding(.bottom, 4)
            ForEach(Array(model.actions.enumerated()), id: \.element) { i, action in
                let on = i == model.actionIndex
                HStack(spacing: 10) {
                    Text("\(i + 1)").font(Leaf.font(11, .semibold)).monospacedDigit()
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 5).fill(on ? Leaf.fresh.opacity(0.45) : Color.primary.opacity(0.06)))
                    Image(systemName: action.symbol).font(.system(size: 13)).frame(width: 18)
                    Text(String(localized: action.title)).font(Leaf.font(13))
                    Spacer()
                }
                .foregroundStyle(on ? Leaf.ink : Color.primary)
                .padding(.horizontal, 8).frame(height: 32)
                .background { if on { tile(true) } }
                .contentShape(Rectangle())
                .onTapGesture { model.actionIndex = i; runAction(action) }
            }
            Spacer(minLength: 0)
            Text("↩ or 1–8 · esc goes back").font(Leaf.font(11)).opacity(0.45).padding(.horizontal, 8)
        }
        .padding(10)
    }

    // MARK: Preview

    @ViewBuilder
    var preview: some View {
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
    func highlighted(_ text: String) -> AttributedString {
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
