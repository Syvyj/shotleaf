import Core
import AppKit
import Carbon.HIToolbox

/// A global shortcut: one of the presets, or one the user recorded. A recorded
/// shortcut round-trips through its `id` ("custom:<keyCode>:<modifiers>:<title>"),
/// so settings store just a string.
public struct HotkeyShortcut: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    let keyCode: UInt32
    let modifiers: UInt32

    public static let all: [HotkeyShortcut] = [
        HotkeyShortcut(id: "cmd-shift-space", title: "⌘⇧Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey)),
        HotkeyShortcut(id: "ctrl-opt-space", title: "⌃⌥Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)),
        HotkeyShortcut(id: "opt-space", title: "⌥Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)),
        HotkeyShortcut(id: "ctrl-space", title: "⌃Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey)),
        HotkeyShortcut(id: "cmd-shift-a", title: "⌘⇧A", keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey | shiftKey)),
    ]
    /// ⌥Space / ⌃Space are often taken by input-source switching, hence ⌘⇧Space.
    public static let `default` = all[0]

    init(id: String, title: String, keyCode: UInt32, modifiers: UInt32) {
        self.id = id
        self.title = title
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(customKeyCode keyCode: UInt32, modifiers: UInt32, title: String) {
        self.init(id: "custom:\(keyCode):\(modifiers):\(title)", title: title, keyCode: keyCode, modifiers: modifiers)
    }

    public static func with(id: String?) -> HotkeyShortcut {
        if let id, id.hasPrefix("custom:") {
            let parts = id.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
            if parts.count == 4, let code = UInt32(parts[1]), let mods = UInt32(parts[2]) {
                return HotkeyShortcut(customKeyCode: code, modifiers: mods, title: String(parts[3]))
            }
        }
        return all.first { $0.id == id } ?? .default
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

/// Global hotkey via Carbon's RegisterEventHotKey — the standard, dependency-free
/// way to get a system-wide shortcut on macOS. Needs no TCC permission.
public final class GlobalHotkeyService: HotkeyService, @unchecked Sendable {
    public let events: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    private let identifier: String
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    public private(set) var shortcut: HotkeyShortcut = .default

    public init(identifier: String = "toggle-panel") {
        self.identifier = identifier
        (events, continuation) = AsyncStream.makeStream()
    }

    /// Returns false if the shortcut couldn't be registered (usually: another app
    /// already owns it). Safe to call again after `stop()`.
    @discardableResult
    public func start() -> Bool {
        guard hotKeyRef == nil else { return true }
        return register(shortcut)
    }

    /// Switches to `new`. If it can't be registered, the previous shortcut stays
    /// active and false is returned.
    @discardableResult
    public func setShortcut(_ new: HotkeyShortcut) -> Bool {
        guard new != shortcut || hotKeyRef == nil else { return true }
        let previous = shortcut
        stop()
        if register(new) { shortcut = new; return true }
        _ = register(previous)
        return false
    }

    public func stop() {
        if let handlerRef { RemoveEventHandler(handlerRef); self.handlerRef = nil }
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
    }

    private func register(_ shortcut: HotkeyShortcut) -> Bool {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // C callback: no captures, so it converts to a function pointer. We pass
        // `self` through userData and recover it inside.
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let service = Unmanaged<GlobalHotkeyService>.fromOpaque(userData).takeUnretainedValue()
            service.continuation.yield(HotkeyEvent(identifier: service.identifier))
            return noErr
        }
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            callback, 1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        let hotKeyID = EventHotKeyID(signature: OSType(0x4150_494C), id: 1) // 'APIL'
        let registered = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard installed == noErr, registered == noErr else {
            stop()
            return false
        }
        return true
    }
}
