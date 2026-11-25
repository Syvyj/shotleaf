import AVKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// The window after a recording: the video, a trim bar, and what to do with the
/// kept part. ↩ copies the MP4 (paste it into a chat with ⌘V), esc closes.
struct RecordingView: View {
    let model: RecordingModel
    let videoSize: CGSize
    let close: () -> Void
    @State private var player: AVPlayer
    @State private var busy = false
    /// The encode in flight; closing cancels it so a late result never reaches the clipboard.
    @State private var job: Task<Void, Never>?
    @State private var toast: String?
    @AppStorage(ScreenshotView.closeAfterCopyKey) private var closeAfterCopy = true

    /// Room for the action row.
    static let minWidth: CGFloat = 560

    init(model: RecordingModel, videoSize: CGSize, close: @escaping () -> Void) {
        self.model = model
        self.videoSize = videoSize
        self.close = close
        _player = State(initialValue: AVPlayer(url: model.original))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            PlayerView(player: player)
                .frame(width: videoSize.width, height: videoSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(maxWidth: .infinity)
                .overlay(alignment: .top) { toastPill }
                .onReceive(player.publisher(for: \.rate)) { rate in
                    // Play pressed at the end of the kept part (or outside it): start over from its start.
                    let now = player.currentTime().seconds
                    if rate > 0, now >= end - 0.05 || now < start {
                        player.seek(to: model.range.start, toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                }
            HStack(spacing: 10) {
                TrimBar(start: start, end: end, duration: model.duration) { start, end, moved in
                    model.range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                              end: CMTime(seconds: end, preferredTimescale: 600))
                    player.currentItem?.forwardPlaybackEndTime = model.range.end
                    player.seek(to: CMTime(seconds: moved, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                }
                .disabled(busy)
                Text(verbatim: RecordingController.elapsed(end - start))
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).opacity(0.6)
            }
            actions
        }
        .padding(14)
        .frame(minWidth: Self.minWidth, alignment: .topLeading)
        .leafPanelChrome()
    }

    private var start: Double { model.range.start.seconds }
    private var end: Double { min(model.range.end.seconds, model.duration) }

    private var header: some View {
        HStack(spacing: 8) {
            BrandLogo()
            VStack(alignment: .leading, spacing: 0) {
                Text("Recording").font(Leaf.font(15, .semibold))
                Text(verbatim: "\(Int(model.size.width)) × \(Int(model.size.height))")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced)).opacity(0.5)
            }
            if busy { ProgressView().controlSize(.small) }
            Spacer()
        }
        .overlay(WindowDragArea())
    }

    private var actions: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) { buttons }.disabled(busy)
            Spacer()
            Button(action: closeWindow) { keyed("Close", "esc") }
                .buttonStyle(LeafButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder private var buttons: some View {
            Button { run(copied: "Copied") { try await model.copy() } } label: { keyed("Copy", "↩") }
                .buttonStyle(LeafButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
            Button { flash(String(localized: "Drag it into any app")) } label: { Text("Drag") }
                .buttonStyle(LeafButtonStyle())
                .onDrag { dragProvider(.mpeg4Movie, model.current) }
                .instantTip("Drag the video into a chat or a folder", above: true)
            Button {
                run(copied: nil) {
                    guard let url = try await model.save() else { return }
                    flash(String(localized: "Saved to \(url.deletingLastPathComponent().lastPathComponent)"))
                }
            } label: { Text("Save") }
                .buttonStyle(LeafButtonStyle())
            Button { run(copied: "Copied · GIF") { try await model.copyGIF() } } label: { Text(verbatim: "GIF") }
                .buttonStyle(LeafButtonStyle())
                .onDrag { dragProvider(.gif, model.gif) }
                .instantTip("Make a GIF and copy it — or drag it out", above: true)
            limitMenu
    }

    /// "Under 8 MB ▾": the size every button's file fits; remembered for the next recording.
    private var limitMenu: some View {
        Menu {
            ForEach(RecordingModel.limits, id: \.self) { limit in
                Button { pick(limit) } label: { Text(verbatim: "\(model.limit == limit ? "✓ " : "")\(SmallFile.label(limit))") }
            }
            Button { pick(nil) } label: { Text(verbatim: "\(model.limit == nil ? "✓ " : "")\(String(localized: "Original"))") }
        } label: {
            Text(model.limit.map { String(localized: "Under \(SmallFile.label($0))") } ?? String(localized: "Original"))
                .frame(height: 17)
        }
        .menuStyle(.button).buttonStyle(LeafButtonStyle()).fixedSize()
    }

    private func pick(_ limit: Int?) {
        model.limit = limit
        ScreenshotWindows.settings.smallVideoLimit = limit ?? 0
    }

    /// The drop asks for the file when it lands, so a fit under a size or a GIF can finish first.
    private func dragProvider(_ type: UTType, _ file: @escaping @MainActor () async throws -> URL) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { done in
            Task { @MainActor in
                do { done(try await file(), false, nil) } catch {
                    report(error)
                    done(nil, false, error)
                }
            }
            return nil
        }
        return provider
    }

    private func closeWindow() {
        job?.cancel()
        close()
    }

    /// Runs an action with the buttons off and a spinner; `copied`: what to say, then close if Settings say so.
    private func run(copied: LocalizedStringResource?, _ action: @escaping () async throws -> Void) {
        busy = true
        job = Task {
            defer { busy = false }
            do {
                try await action()
                guard let copied else { return }
                flash(String(localized: copied))
                if closeAfterCopy {
                    try await Task.sleep(for: .milliseconds(450)) // long enough to see "Copied"
                    close()
                }
            } catch {
                report(error)
            }
        }
    }

    /// A beep and why (nothing once the window was closed).
    private func report(_ error: Error) {
        switch error {
        case is CancellationError: return
        case VideoEditError.tooLong:
            NSSound.beep()
            flash(String(localized: "Too long for \(SmallFile.label(model.limit ?? 0)) — trim it"))
        default:
            NSSound.beep()
            flash(String(localized: "Couldn’t make the video file"))
        }
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { if toast == text { toast = nil } }
        }
    }

    @ViewBuilder private var toastPill: some View {
        if let toast {
            Text(verbatim: toast)
                .font(Leaf.font(12, .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Leaf.leaf, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                .fixedSize()
                .padding(.top, 10)
                .allowsHitTesting(false)
        }
    }

    private func keyed(_ title: LocalizedStringKey, _ key: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
            Text(verbatim: key).font(Leaf.font(10.5, .semibold)).opacity(0.5)
        }
    }
}

/// A track with two handles: the part of the recording to keep, at least half a second.
struct TrimBar: View {
    let start: Double
    let end: Double
    let duration: Double
    /// New start and end, and the time under the handle that moved (for the preview).
    let changed: (Double, Double, Double) -> Void
    /// Where the handle being dragged was when grabbed, so it doesn't jump to the pointer.
    @State private var grabbed: Double?

    enum Handle { case start, end }
    static let minLength = 0.5
    private static let handleWidth: CGFloat = 10

    /// Within the recording, the moved handle giving way to keep `minLength` (or the whole of a shorter one).
    static func clamped(start: Double, end: Double, duration: Double, moving: Handle) -> (Double, Double) {
        let gap = min(minLength, duration)
        let start = min(max(start, 0), duration), end = min(max(end, 0), duration)
        switch moving {
        case .start:
            let s = max(min(start, end - gap), 0)
            return (s, max(end, s + gap))
        case .end:
            let e = min(max(end, start + gap), duration)
            return (min(start, e - gap), e)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let track = max(geo.size.width - 2 * Self.handleWidth, 1)
            let x = { (t: Double) in Self.handleWidth + CGFloat(duration > 0 ? t / duration : 0) * track }
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.1)).frame(height: 8)
                Rectangle().fill(Leaf.lime.opacity(0.7))
                    .frame(width: max(x(end) - x(start), 0), height: 8)
                    .offset(x: x(start))
                handle(.start, at: x(start) - Self.handleWidth, track: track)
                handle(.end, at: x(end), track: track)
            }
            .frame(maxHeight: .infinity)
            .coordinateSpace(name: "trim")
        }
        .frame(height: 26)
    }

    private func handle(_ which: Handle, at offset: CGFloat, track: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Leaf.leaf)
            .frame(width: Self.handleWidth, height: 26)
            .offset(x: offset)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trim")).onChanged { drag in
                let from = grabbed ?? (which == .start ? start : end)
                if grabbed == nil { grabbed = from }
                let t = from + Double(drag.translation.width / track) * duration
                let (s, e) = Self.clamped(start: which == .start ? t : start, end: which == .end ? t : end,
                                          duration: duration, moving: which)
                changed(s, e, which == .start ? s : e)
            }.onEnded { _ in grabbed = nil })
            .accessibilityLabel(Text(which == .start ? "Start" : "End"))
    }
}

/// AVKit's player with just a play button (the trim bar does the rest).
private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .minimal
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}
}
