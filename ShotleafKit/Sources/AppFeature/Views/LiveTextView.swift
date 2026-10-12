import SwiftUI
import VisionKit

/// macOS Live Text over the shot: select words or lines like in Preview.
/// The overlay is owned by the screenshot view, which reads its selection.
struct LiveTextView: NSViewRepresentable {
    let overlay: ImageAnalysisOverlayView
    let image: CGImage

    func makeNSView(context: Context) -> ImageAnalysisOverlayView {
        overlay.preferredInteractionTypes = .textSelection
        let image = image
        Task { @MainActor [overlay] in
            overlay.analysis = try? await ImageAnalyzer().analyze(image, orientation: .up, configuration: .init(.text))
            overlay.selectableItemsHighlighted = true
        }
        return overlay
    }

    func updateNSView(_ nsView: ImageAnalysisOverlayView, context: Context) {}
}
