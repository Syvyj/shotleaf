import SwiftUI
import AppKit
import VisionKit
import UniformTypeIdentifiers

/// The editor's bottom row: the actions, their keys and what they do.
extension ScreenshotView {
    // MARK: Toolbar

    /// Actions with their keys on them — one row instead of buttons + hints.
    /// The action row; drops the key hints when the window is too narrow for them.
    var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            actionRow(keys: true)
            actionRow(keys: false)
        }
    }

    func actionRow(keys: Bool) -> some View {
        HStack(spacing: 6) {
            Button { copy() } label: { keyed(liveText == nil ? "Copy" : "Copy text", "⌘C", show: keys) }
                .buttonStyle(LeafButtonStyle(prominent: true))
                .keyboardShortcut("c", modifiers: .command)
            HStack(spacing: 2) {
                Button {
                    if let url = actions.save() { flash(String(localized: "Saved to \(url.deletingLastPathComponent().lastPathComponent)")) }
                } label: { keyed("Save", "⌘S", show: keys) }
                .keyboardShortcut("s", modifiers: .command)
                Button { flyout = flyout == .saveAs ? nil : .saveAs } label: { chevron.frame(height: 17) }
                    .instantTip("Save as…", hidden: flyout == .saveAs, above: true)
            }
            .buttonStyle(LeafButtonStyle())
            .overlay(alignment: .bottomLeading) {
                if flyout == .saveAs {
                    flyoutCard(above: true) {
                        Button {
                            flyout = nil
                            let folder = actions.toSnippets()
                            flash(folder.map { String(localized: "Saved to “\($0)”") } ?? String(localized: "Saved as a snippet"))
                        } label: {
                            Text("To Snippets").font(Leaf.font(13, .medium))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .frame(width: 150, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        ForEach([UTType.png, .jpeg, .heic, .pdf], id: \.self) { type in
                            Button { flyout = nil; actions.saveAs(type) } label: {
                                Text(verbatim: "\(type.preferredFilenameExtension?.uppercased() ?? "")…")
                                    .font(Leaf.font(13, .medium))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .frame(width: 150, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(SmallFile.limits, id: \.self) { limit in
                            Button { flyout = nil; actions.saveSmall(limit) } label: {
                                Text("JPEG under \(SmallFile.label(limit))…")
                                    .font(Leaf.font(13, .medium))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .frame(width: 150, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Button { actions.pin() } label: { keyed("Pin", "P", show: keys) }
                .buttonStyle(LeafButtonStyle())
                .keyboardShortcut("p", modifiers: [])
            Button { actions.share() } label: { Image(systemName: "square.and.arrow.up").frame(height: 17) }
                .buttonStyle(LeafButtonStyle())
                .instantTip("Share", above: true)
            if ShotLinks.isSetUp { // the free service, or the user's own server (Settings → Screenshot Links)
                HStack(spacing: 2) {
                    Button { makeLink(ShotLinks.defaultHours) } label: {
                        if linking { ProgressView().controlSize(.small).frame(height: 17) } else { Image(systemName: "link").frame(height: 17) }
                    }
                    .instantTip(String(localized: "Link for \(ShotLinks.defaultHours) h"), hidden: flyout == .link, above: true)
                    Button { flyout = flyout == .link ? nil : .link } label: { chevron.frame(height: 17) }
                }
                .buttonStyle(LeafButtonStyle())
                .disabled(linking)
                .overlay(alignment: .bottomLeading) {
                    if flyout == .link {
                        flyoutCard(above: true) {
                            ForEach(ShotLinks.choices, id: \.self) { hours in
                                Button { flyout = nil; makeLink(hours) } label: {
                                    Text("For \(hours) h").font(Leaf.font(13, .medium))
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .frame(width: 120, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            if ShotLinks.last != nil {
                                Divider().padding(.vertical, 2)
                                Button { flyout = nil; deleteLink() } label: {
                                    Text("Delete last link").font(Leaf.font(13, .medium))
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .frame(width: 120, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            Button { flyout = flyout == .watermark ? nil : .watermark } label: { Image(systemName: "signature").frame(height: 17) }
                .buttonStyle(LeafButtonStyle(prominent: doc.watermark != nil))
                .instantTip("Watermark", hidden: flyout == .watermark, above: true)
                .overlay(alignment: .bottomLeading) {
                    if flyout == .watermark { flyoutCard(above: true) { watermarkPanel } }
                }
            Button { toggleLiveText() } label: { keyed("Text", "T", show: keys) }
                .buttonStyle(LeafButtonStyle(prominent: liveText != nil))
                .keyboardShortcut("t", modifiers: [])
                .instantTip(liveText == nil ? "Select text on the shot" : "Back to marks", above: true)
            Spacer(minLength: 6)
            if doc.crop != nil {
                Button("Apply crop") { doc.applyCrop(original: cgImage, size: displaySize) }
                    .buttonStyle(LeafButtonStyle(prominent: true))
                    .instantTip("Keep only the cropped area — ⌘Z brings the rest back", above: true)
            }
            if doc.selection != nil {
                Button { if let id = doc.selection { doc.remove(id) } } label: { keyed("Delete", "⌫", show: keys) }
                    .buttonStyle(LeafButtonStyle())
            }
            Button { doc.undo() } label: { keyed("Undo", "⌘Z", show: keys) }
                .buttonStyle(LeafButtonStyle())
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!doc.canUndo)
                .opacity(doc.canUndo ? 1 : 0.4)
            Button { actions.close() } label: { keyed("Close", "esc", show: keys) }
                .buttonStyle(LeafButtonStyle())
        }
        .disabled(editingText)
        .fixedSize(horizontal: false, vertical: true)
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

    /// Esc, ↩, ⌫ and tool keys — off while typing a text mark (they belong to
    /// the field then), except esc, which always drops the text being typed.
    @ViewBuilder
    var keyboard: some View {
        if editingText || flyout == .watermark { // typing: the letters belong to the field
            Button("") { textDraft = nil; editingTextID = nil; doc.tool = nil; flyout = nil }
                .keyboardShortcut(.cancelAction)
        } else {
            Button("") {
                if flyout != nil { flyout = nil }
                else if liveText != nil { liveText = nil }
                else if doc.selection != nil { doc.selection = nil }
                else if doc.tool != nil { doc.tool = nil }
                else { actions.close() }
            }
            .keyboardShortcut(.cancelAction)
            Button("") { copy(); actions.close() }
                .keyboardShortcut(.defaultAction)
            Button("") { if let id = doc.selection { doc.remove(id) } }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(doc.selection == nil)
            Button("") { doc.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!doc.canRedo)
            Button("") { pick(nil) }.keyboardShortcut("0", modifiers: [])
            Button("") { pastePicture() }.keyboardShortcut("v", modifiers: .command)
            ForEach(AnnotationTool.allCases) { tool in
                if let key = tool.key {
                    Button("") { pick(tool) }.keyboardShortcut(KeyEquivalent(key), modifiers: [])
                }
            }
        }
    }

    /// The image — or, in Live Text mode, the selected text (all of it when
    /// nothing is selected).
    func copy() {
        guard let liveText else { actions.copy(); flash("Copied"); closeAfterCopying(); return }
        let text = liveText.selectedText.isEmpty ? liveText.analysis?.transcript ?? "" : liveText.selectedText
        guard !text.isEmpty else { flash("No text found"); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flash(liveText.selectedText.isEmpty ? "Copied all text" : "Copied")
        closeAfterCopying()
    }

    /// The job is done once it's copied (Settings → Screenshots can keep the window open).
    func closeAfterCopying() {
        guard closeAfterCopy else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(450)) // long enough to see "Copied"
            actions.close()
        }
    }

    /// Uploads, then puts the link on the clipboard.
    func makeLink(_ hours: Int) {
        linking = true
        Task {
            defer { linking = false }
            do {
                let url = try await actions.link(hours)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                Sound.copied()
                flash(String(localized: "Link copied · works \(hours) h"))
            } catch {
                flash(error.localizedDescription)
            }
        }
    }

    /// Takes the last link's picture off the server, before it expires.
    func deleteLink() {
        linking = true
        Task {
            defer { linking = false }
            do {
                try await ShotLinks.deleteLast()
                flash(String(localized: "Link deleted"))
            } catch {
                flash(error.localizedDescription)
            }
        }
    }

    /// ⌘V: the clipboard's picture on top of the shot, selected, to move and resize.
    func pastePicture() {
        guard let pasted = NSImage(pasteboard: .general),
              let picture = pasted.cgImage(forProposedRect: nil, context: nil, hints: nil) else { NSSound.beep(); return }
        let frame = AnnotationEditing.pastedFrame(pixels: CGSize(width: picture.width, height: picture.height),
                                                  pixelsPerPoint: picturePixels.width / max(pictureSize.width, 1), picture: pictureSize)
        pick(nil)
        doc.add(.image(picture, frame))
    }

    func toggleLiveText() {
        if liveText != nil { liveText = nil; return }
        doc.tool = nil
        doc.selection = nil
        liveText = ImageAnalysisOverlayView()
        flash("Select text · ⌘C copies it")
    }

    func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { if toast == text { toast = nil } }
        }
    }
}
