import SwiftUI

/// The parts of Shotleaf that can be turned off (Settings → General → Tools).
/// An off tool leaves the menu, frees its shortcuts and stops its background work.
public enum Tool: String, CaseIterable, Identifiable, Sendable {
    case screenshots, screenText, clipboard, snippets, completion
    public var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .screenshots: "Screenshots"
        case .screenText: "Text from Screenshot"
        case .clipboard: "Clipboard History"
        case .snippets: "Snippets"
        case .completion: "Text completion"
        }
    }

    var actions: [HotkeyAction] {
        switch self {
        case .screenshots: [.capture, .scrolling, .editLast, .editClipboard]
        case .screenText: [.screenshotText]
        case .clipboard: [.clipboard]
        case .snippets: [.snippets]
        case .completion: []
        }
    }

    static func owning(_ action: HotkeyAction) -> Tool? { allCases.first { $0.actions.contains(action) } }

    static let offKey = "toolsOff"
    static var savedOff: Set<Tool> { Set((UserDefaults.standard.stringArray(forKey: offKey) ?? []).compactMap(Tool.init)) }
}
