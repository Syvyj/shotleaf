import Core
import AppKit
import Carbon.HIToolbox

/// A global shortcut: an action's default, or one the user recorded. A recorded
/// shortcut round-trips through its `id` ("custom:<keyCode>:<modifiers>:<title>"),
/// so settings store just a string.
public struct HotkeyShortcut: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    let keyCode: UInt32
    let modifiers: UInt32

    /// Defaults for the screenshot actions: ⌘⇧1 text, ⌘⇧2 screenshot, ⌘⇧3
    /// scrolling. ⌘⇧3 is macOS's own full-screen shot until it's switched off
    /// in System Settings → Keyboard → Keyboard Shortcuts → Screenshots.
    public static let screenshotDefault = HotkeyShortcut( // text from screenshot
        id: "cmd-shift-1", title: "⌘⇧1", keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(cmdKey | shiftKey)
    )
    public static let captureDefault = HotkeyShortcut(
        id: "cmd-shift-2", title: "⌘⇧2", keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey)
    )
    public static let scrollingDefault = HotkeyShortcut(
        id: "cmd-shift-3", title: "⌘⇧3", keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey | shiftKey)
    )
    public static let editLastDefault = HotkeyShortcut(
        id: "ctrl-opt-cmd-e", title: "⌃⌥⌘E", keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(controlKey | optionKey | cmdKey)
    )
    public static let clipboardDefault = HotkeyShortcut(
        id: "shift-cmd-v", title: "⇧⌘V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(shiftKey | cmdKey)
    )
    public static let snippetsDefault = HotkeyShortcut(
        id: "shift-cmd-b", title: "⇧⌘B", keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(shiftKey | cmdKey)
    )
    public static let editClipboardDefault = HotkeyShortcut(
        id: "ctrl-opt-cmd-v", title: "⌃⌥⌘V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey | cmdKey)
    )

    init(id: String, title: String, keyCode: UInt32, modifiers: UInt32) {
        self.id = id
        self.title = title
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(customKeyCode keyCode: UInt32, modifiers: UInt32, title: String) {
        self.init(id: "custom:\(keyCode):\(modifiers):\(title)", title: title, keyCode: keyCode, modifiers: modifiers)
    }

    /// nil for an unknown id.
    public static func with(id: String?) -> HotkeyShortcut? {
        if let id, id.hasPrefix("custom:") {
            let parts = id.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
            if parts.count == 4, let code = UInt32(parts[1]), let mods = UInt32(parts[2]) {
                return HotkeyShortcut(customKeyCode: code, modifiers: mods, title: String(parts[3]))
            }
        }
        return [captureDefault, screenshotDefault, scrollingDefault, editLastDefault, editClipboardDefault, clipboardDefault, snippetsDefault].first { $0.id == id }
    }

    /// Builds a shortcut from a key press in the recorder. Nil when it has no
    /// ⌘/⌥/⌃ modifier (a bare key or ⇧+key would hijack normal typing), except
    /// for F-keys, which are safe on their own.
    public static func recorded(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?) -> HotkeyShortcut? {
        let flags = flags.intersection([.command, .option, .control, .shift])
        let functionKey = functionKeyNames[keyCode]
        guard functionKey != nil || !flags.intersection([.command, .option, .control]).isEmpty else { return nil }

        var modifiers = 0
        var symbols = ""
        // Apple's display order: ⌃⌥⇧⌘.
        if flags.contains(.control) { modifiers |= controlKey; symbols += "⌃" }
        if flags.contains(.option) { modifiers |= optionKey; symbols += "⌥" }
        if flags.contains(.shift) { modifiers |= shiftKey; symbols += "⇧" }
        if flags.contains(.command) { modifiers |= cmdKey; symbols += "⌘" }

        let key = functionKey ?? namedKeys[keyCode] ?? (characters ?? "").uppercased()
        guard !key.isEmpty else { return nil }
        return HotkeyShortcut(customKeyCode: UInt32(keyCode), modifiers: UInt32(modifiers), title: symbols + key)
    }

    private static let namedKeys: [UInt16: String] = [
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Delete): "⌫", UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
    ]

    private static let functionKeyNames: [UInt16: String] = [
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
    ]
}

/// Actions with their own (optional) global shortcut.
public enum HotkeyAction: String, CaseIterable, Identifiable, Sendable {
    case capture                            // screenshot → preview window
    case screenshotText = "screenshot-text" // screenshot → OCR text
    case scrolling                          // scrolling screenshot → preview window
    case editLast = "edit-last"             // the last screenshot back in the editor
    case editClipboard = "edit-clipboard"   // an image from the clipboard in the editor
    case clipboard                          // the clipboard history panel
    case snippets                           // the same panel, on its Snippets tab

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .capture: String(localized: "Screenshot")
        case .screenshotText: String(localized: "Text from Screenshot")
        case .scrolling: String(localized: "Scrolling Screenshot")
        case .editLast: String(localized: "Edit Last Screenshot")
        case .editClipboard: String(localized: "Edit Image from Clipboard")
        case .clipboard: String(localized: "Clipboard History")
        case .snippets: String(localized: "Snippets")
        }
    }

    public var defaultShortcut: HotkeyShortcut {
        switch self {
        case .capture: .captureDefault
        case .screenshotText: .screenshotDefault
        case .scrolling: .scrollingDefault
        case .editLast: .editLastDefault
        case .editClipboard: .editClipboardDefault
        case .clipboard: .clipboardDefault
        case .snippets: .snippetsDefault
        }
    }
}

/// Global hotkeys via Carbon's RegisterEventHotKey — the standard, dependency-free
/// way to get system-wide shortcuts on macOS. Needs no TCC permission. Several
/// hotkeys at once, each under a string id ("panel", "screenshot-text"…);
/// a press is emitted as `HotkeyEvent(identifier: id)`.
public final class GlobalHotkeyService: HotkeyService, @unchecked Sendable {
    public let events: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    private var handlerRef: EventHandlerRef?
    /// What the user chose; survives stop()/start() (pause while recording).
    private var wanted: [String: HotkeyShortcut] = [:]
    /// What is registered with Carbon right now, by Carbon's numeric id.
    private var active: [UInt32: (id: String, ref: EventHotKeyRef)] = [:]
    private var nextNumber: UInt32 = 1

    public init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    public func shortcut(for id: String) -> HotkeyShortcut? { wanted[id] }

    /// Registers every chosen hotkey. False if any couldn't be registered.
    /// Safe to call again after `stop()`.
    @discardableResult
    public func start() -> Bool {
        installHandlerIfNeeded()
        var allOK = true
        for (id, shortcut) in wanted where !isActive(id) {
            allOK = register(shortcut, as: id) && allOK
        }
        return allOK
    }

    /// Unregisters everything (choices are kept for the next `start()`).
    public func stop() {
        for (_, entry) in active { UnregisterEventHotKey(entry.ref) }
        active = [:]
        if let handlerRef { RemoveEventHandler(handlerRef); self.handlerRef = nil }
    }

    /// Sets (or with nil, removes) the hotkey for `id`. If the new one can't be
    /// registered — taken by another app, or by another Shotleaf hotkey — the
    /// previous one stays and false is returned.
    @discardableResult
    public func setShortcut(_ new: HotkeyShortcut?, for id: String) -> Bool {
        let previous = wanted[id]
        unregister(id)
        guard let new else {
            wanted[id] = nil
            return true
        }
        let clash = wanted.contains { $0.key != id && $0.value.keyCode == new.keyCode && $0.value.modifiers == new.modifiers }
        installHandlerIfNeeded()
        if !clash, register(new, as: id) {
            wanted[id] = new
            return true
        }
        if let previous { _ = register(previous, as: id) }
        return false
    }

    // MARK: Carbon

    private func isActive(_ id: String) -> Bool { active.values.contains { $0.id == id } }

    private func unregister(_ id: String) {
        for (number, entry) in active where entry.id == id {
            UnregisterEventHotKey(entry.ref)
            active[number] = nil
        }
    }

    private func register(_ shortcut: HotkeyShortcut, as id: String) -> Bool {
        let number = nextNumber
        nextNumber += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4150_494C), id: number) // 'APIL'
        guard RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr,
              let ref
        else { return false }
        active[number] = (id, ref)
        return true
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // C callback: no captures, so it converts to a function pointer. `self`
        // travels through userData; the pressed hotkey's number through the event.
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            let service = Unmanaged<GlobalHotkeyService>.fromOpaque(userData).takeUnretainedValue()
            if let id = service.active[hotKeyID.id]?.id {
                service.continuation.yield(HotkeyEvent(identifier: id))
            }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
    }
}
