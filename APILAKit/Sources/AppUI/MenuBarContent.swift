import SwiftUI

/// Content shown from the menu bar item. Kept free of app-specific wiring;
/// real state will be injected via the SwiftUI environment later.
public struct MenuBarContent: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("APILA").font(.headline)
            Text("AI Productivity Suite")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Text("Foundation skeleton — features land in upcoming iterations.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 260)
    }
}
