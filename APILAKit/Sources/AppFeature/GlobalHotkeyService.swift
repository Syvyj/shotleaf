import Core
import AppKit
import Carbon.HIToolbox

/// A choosable global shortcut. A fixed list instead of a key recorder: covers
/// the sane options with zero custom UI.
/// ponytail: preset list; add a key-recorder field if users ask for arbitrary combos.
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

    public static func with(id: String?) -> HotkeyShortcut {
        all.first { $0.id == id } ?? .default
    }
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
