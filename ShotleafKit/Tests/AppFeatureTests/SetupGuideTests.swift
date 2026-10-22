import Testing
import Core
import Foundation
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
