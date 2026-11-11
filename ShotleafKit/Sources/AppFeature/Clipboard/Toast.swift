import AppKit
import Core
import SwiftUI

/// A short note at the top of the screen with the mouse (the queue's progress…).
@MainActor
enum Toast {
    private static var panel: FloatingPanel?
    private static var hide: Task<Void, Never>?

    static func show(_ text: String) {
        panel?.orderOut(nil)
        let view = Text(text)
            .font(Leaf.font(13, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Capsule().fill(Leaf.leaf))
            .padding(8)
        let new = ScreenshotWindows.makePanel(view)
        new.ignoresMouseEvents = true
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        new.setFrameOrigin(CGPoint(x: visible.midX - new.frame.width / 2, y: visible.maxY - new.frame.height - 12))
        new.orderFrontRegardless()
        panel = new
        hide?.cancel()
        hide = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
            panel = nil
        }
    }
}
