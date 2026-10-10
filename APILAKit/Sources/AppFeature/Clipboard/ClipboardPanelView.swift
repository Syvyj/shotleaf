import SwiftUI

/// The ⌃⌘V panel: search on top, type chips, the list (1–9 on the first rows)
/// and a preview of the selected entry, key hints at the bottom.
struct ClipboardPanelView: View {
    @Bindable var model: ClipboardPanelModel
    let pick: (ClipItem, ClipboardPanelController.Mode) -> Void
    let close: () -> Void
    @FocusState private var searching: Bool

    var body: some View {
        let results = model.results
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(Leaf.ink)
                TextField("Search the clipboard", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(Leaf.font(16))
                    .focused($searching)
                if model.history.isPaused {
                    Text("Paused").font(Leaf.font(11, .semibold)).foregroundStyle(Leaf.ink)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Leaf.ink.opacity(0.12)))
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            .overlay(WindowDragArea().allowsHitTesting(false))

            HStack(spacing: 6) {
                ForEach(ClipboardPanelModel.kinds, id: \.self) { kind in
                    Button { model.kind = kind } label: {
                        Text(Self.title(kind)).font(Leaf.font(12, .semibold))
                            .foregroundStyle(model.kind == kind ? Leaf.ink : Color.primary.opacity(0.65))
                            .padding(.horizontal, 10).frame(height: 24)
                            .background(Capsule().fill(model.kind == kind ? AnyShapeStyle(Leaf.selection) : AnyShapeStyle(.primary.opacity(0.05))))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 8)

            Divider().opacity(0.5)
            HStack(spacing: 0) {
                list(results).frame(width: 380)
                Divider().opacity(0.5)
                preview.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Divider().opacity(0.5)
            hints
        }
        .frame(width: 720, height: 460)
        .leafPanelChrome()
        .onAppear { searching = true }
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
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? AnyShapeStyle(Leaf.selection) : AnyShapeStyle(.clear)))
        .contentShape(Rectangle())
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

    private var hints: some View {
        HStack(spacing: 14) {
            hint("↩", "paste"); hint("⌥↩", "plain text"); hint("⌘↩", "copy only"); hint("⌘P", "pin"); hint("⌘⌫", "delete"); hint("Tab", "type")
            if model.current?.hasImage == true { hint("⌘E", "edit") }
            Spacer()
            hint("esc", "close")
        }
        .padding(.horizontal, 14).frame(height: 34)
    }

    private func hint(_ key: String, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Keycap(key: key)
            Text(title).font(Leaf.font(11)).opacity(0.6)
        }
    }

    // MARK: Texts

    static func title(_ kind: ClipItem.Kind?) -> LocalizedStringKey {
        switch kind {
        case nil: "All"
        case .text?: "Text"
        case .link?: "Links"
        case .image?: "Images"
        case .color?: "Colors"
        case .file?: "Files"
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
