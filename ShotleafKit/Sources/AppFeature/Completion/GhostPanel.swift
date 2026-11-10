import AppKit

/// The grey suggestion right after the caret: a click-through, never-key panel.
@MainActor
final class GhostPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        label.textColor = NSColor.tertiaryLabelColor
        label.lineBreakMode = .byClipping
        label.wantsLayer = true
        label.layer?.cornerRadius = 5
        label.layer?.masksToBounds = true
        contentView = label
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private var caret = CGRect.zero

    func show(text: String, caret: CGRect) {
        self.caret = caret
        label.textColor = NSColor.tertiaryLabelColor
        label.drawsBackground = false
        // Roughly the field's font: a line is ~1.2× the font size.
        label.font = Self.font(for: caret)
        update(text: text)
        orderFrontRegardless()
    }

    /// Roughly the field's font: a line is ~1.2× the font size.
    static func font(for caret: CGRect) -> NSFont { .systemFont(ofSize: min(max(caret.height / 1.22, 11), 30)) }

    /// The words of `text` that fit between the caret and `rightEdge`; nil if
    /// not even the first one does.
    static func fitting(_ text: String, caret: CGRect, rightEdge: CGFloat) -> String? {
        let room = rightEdge - caret.maxX - 8
        let attributes: [NSAttributedString.Key: Any] = [.font: font(for: caret)]
        var candidate = text
        while !candidate.trimmingCharacters(in: .whitespaces).isEmpty {
            if NSAttributedString(string: candidate, attributes: attributes).size().width <= room { return candidate }
            guard let cut = candidate.lastIndex(where: \.isWhitespace), cut > candidate.startIndex else { return nil }
            candidate = String(candidate[..<cut])
        }
        return nil
    }

    func update(text: String) {
        badge = false
        label.stringValue = text
        layoutAtCaret()
    }

    /// Mid-line or a quick fix: a small "⇥ text" badge just under the caret.
    func showBadge(_ text: String, caret: CGRect) {
        self.caret = caret
        badge = true
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.stringValue = "⇥  " + text
        label.textColor = .labelColor
        label.drawsBackground = true
        label.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
        layoutAtCaret()
        orderFrontRegardless()
    }

    private var badge = false

    func move(caret: CGRect) {
        self.caret = caret
        layoutAtCaret()
    }

    private func layoutAtCaret() {
        let size = label.intrinsicContentSize
        if badge { // under the caret, slightly left so the ⇥ sits below it
            setFrame(CGRect(x: caret.maxX - 6, y: caret.minY - size.height - 4, width: size.width + 8, height: size.height + 2), display: true)
            return
        }
        let y = caret.minY + (caret.height - size.height) / 2
        setFrame(CGRect(x: caret.maxX, y: y, width: size.width + 4, height: size.height), display: true)
    }
}
