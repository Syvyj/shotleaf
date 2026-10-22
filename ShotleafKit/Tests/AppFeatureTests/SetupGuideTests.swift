import Testing
import Core
import Foundation
import AppKit
import SwiftUI
@testable import AppFeature

@Suite("Setup guide")
struct SetupGuideTests {
    @Test("Only the permissions the tools that are on still need, screen first")
    func missing() {
        let none: [PermissionKind: PermissionStatus] = [:]
        #expect(Tool.missing(on: Tool.allCases, status: none) == [.screenRecording, .accessibility])
        #expect(Tool.missing(on: [.screenshots], status: none) == [.screenRecording])
        #expect(Tool.missing(on: [.clipboard, .completion], status: none) == [.accessibility])
        #expect(Tool.missing(on: [.screenshots, .snippets], status: [.screenRecording: .granted]) == [.accessibility])
        #expect(Tool.missing(on: [], status: none).isEmpty)
    }
}

@Suite("Editor key hint")
struct EditorHintTests {
    @Test("Shown three times, or until it's closed")
    func times() {
        let defaults = UserDefaults(suiteName: "EditorHintTests")!
        defaults.removePersistentDomain(forName: "EditorHintTests")
        #expect(EditorHint.take(defaults) && EditorHint.take(defaults) && EditorHint.take(defaults))
        #expect(!EditorHint.take(defaults))
        defaults.removePersistentDomain(forName: "EditorHintTests")
        #expect(EditorHint.take(defaults))
        EditorHint.dismiss(defaults)
        #expect(!EditorHint.take(defaults))
    }
}

@Suite("Setup guide pictures")
@MainActor
struct SetupGuidePreviews {
    @Test("Each page renders (pictures only with SHOTLEAF_PREVIEW_DIR)")
    func pages() throws {
        let coordinator = AppCoordinator()
        defer { UserDefaults.standard.removeObject(forKey: OnboardingView.pageKey) }
        for page in OnboardingView.Page.allCases {
            UserDefaults.standard.set(page.rawValue, forKey: OnboardingView.pageKey)
            try renderPreview(OnboardingView(coordinator: coordinator), "guide-\(page.rawValue).png")
        }
    }
}

@Suite("Setup guide picture for the site")
@MainActor
struct SetupGuideSitePicture {
    /// The guide's first page with the app's icon, as a PNG at SHOTLEAF_GUIDE_SHOT (skipped without it).
    @Test("First page, for site/assets/guide/setup-*.webp")
    func picture() throws {
        guard let out = ProcessInfo.processInfo.environment["SHOTLEAF_GUIDE_SHOT"] else { return }
        let icon = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../App/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png").standardized
        NSApplication.shared.applicationIconImage = NSImage(contentsOf: icon)
        let page = ProcessInfo.processInfo.environment["SHOTLEAF_GUIDE_PAGE"] ?? OnboardingView.Page.tools.rawValue
        UserDefaults.standard.set(page, forKey: OnboardingView.pageKey)
        defer { UserDefaults.standard.removeObject(forKey: OnboardingView.pageKey) }
        let view = OnboardingView(coordinator: AppCoordinator()).fixedSize()
            .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .aqua)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        // SHOTLEAF_GUIDE_SCALE: pixels per point (2 for the site, 3 for posts).
        let scale = Double(ProcessInfo.processInfo.environment["SHOTLEAF_GUIDE_SCALE"] ?? "") ?? 2
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * scale),
                                                pixelsHigh: Int(host.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
    }
}
