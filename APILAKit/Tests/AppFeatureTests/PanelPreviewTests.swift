import Testing
import SwiftUI
@testable import Core
@testable import InferenceKit
@testable import ActionKit
@testable import AppFeature

/// Renders the panel to PNGs when APILA_PREVIEW_DIR is set (design check).
@Suite("Panel render")
@MainActor
struct PanelPreviewTests {
    private func panel(_ configure: (PanelViewModel) async throws -> Void) async throws -> PanelViewModel {
        let registry = InferenceProviderRegistry()
        await registry.register(MockStreamingProvider(
            reply: "The quarterly report shows revenue up 12%, driven by the new subscription plans.", perTokenDelayMs: 0
        ), makeCurrent: true)
        let vm = PanelViewModel(
            runner: ActionRunner(context: PreviewContext(), executors: [.inference: InferenceExecutor(registry: registry, recognizer: PreviewOCR())]),
            inserter: ResultInserter(clipboard: PreviewClipboard()),
            actions: BuiltInActions.inferenceActions(),
            accessibilityGranted: { true }
        )
        vm.providerName = "LM Studio · gemma-3-12b"
        vm.present(snapshot: ContextSnapshot(selectedText: "Revenue grew twelve percent this quarter thanks to subscriptions.", capturedAt: Date()), sourceApp: nil)
        try await configure(vm)
        return vm
    }

    private func render(_ vm: PanelViewModel, _ name: String, dark: Bool) throws {
        let view = ZStack {
            LinearGradient(colors: dark ? [Color(white: 0.12), Color(white: 0.2)] : [Color(white: 0.92), Color(white: 0.82)],
                           startPoint: .top, endPoint: .bottom)
            PanelView(vm: vm).shadow(radius: 20, y: 8)
        }
        .frame(width: 560, height: 520)
        .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        if let dir = ProcessInfo.processInfo.environment["APILA_PREVIEW_DIR"],
           let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
    }

    @Test("Actions and result screens render in light and dark")
    func renders() async throws {
        let actions = try await panel { $0.selectedIndex = 2 }
        try render(actions, "panel-actions-light.png", dark: false)
        try render(actions, "panel-actions-dark.png", dark: true)

        let result = try await panel { vm in
            vm.confirm()
            for _ in 0..<200 where vm.screen != .result { try await Task.sleep(for: .milliseconds(5)) }
        }
        try render(result, "panel-result-dark.png", dark: true)
        try render(result, "panel-result-light.png", dark: false)
        #expect(FittingProbe.height(text: "One short line.") < 60)
        #expect(FittingProbe.height(text: String(repeating: "Long text that wraps. ", count: 200)) <= 260)
    }
}

private struct PreviewContext: ContextProviding {
    func snapshot(requirements: ContextRequirements) async throws -> ContextSnapshot { ContextSnapshot(capturedAt: Date()) }
}
private struct PreviewOCR: TextRecognizing {
    func recognizeText(in image: ImagePayload) async throws -> String { "" }
}
private struct PreviewClipboard: ClipboardService {
    func writeText(_ text: String) async throws {}
    func readText() async throws -> String? { nil }
}

@MainActor
private enum FittingProbe {
    /// Height the fitting text box takes inside a 440-pt-wide column.
    static func height(text: String) -> CGFloat {
        let host = NSHostingView(rootView: FittingScrollText(text: text).frame(width: 440))
        return host.fittingSize.height
    }
}
