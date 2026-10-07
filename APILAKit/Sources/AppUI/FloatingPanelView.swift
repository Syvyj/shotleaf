import SwiftUI

/// The floating panel content (shown over any app via a non-activating NSPanel,
/// wired up in a later iteration). Placeholder for now.
public struct FloatingPanelView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("APILA")
                .font(.title3.weight(.semibold))
            Text("Ask, rewrite, translate — anywhere.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 420, height: 180, alignment: .topLeading)
    }
}
