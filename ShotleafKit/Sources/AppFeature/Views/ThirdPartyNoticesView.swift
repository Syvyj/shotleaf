import SwiftUI

/// The licences of the open-source libraries inside Shotleaf (Resources/ThirdPartyNotices.txt).
struct ThirdPartyNoticesView: View {
    let close: () -> Void

    private static let text: String = Bundle.module.url(forResource: "ThirdPartyNotices", withExtension: "txt")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Third-party licences").font(Leaf.font(15, .semibold))
            ScrollView {
                Text(Self.text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Spacer(); Button("Close", action: close).keyboardShortcut(.cancelAction) }
        }
        .padding(16)
        .frame(width: 620, height: 520)
    }
}
