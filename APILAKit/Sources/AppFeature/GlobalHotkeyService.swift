import Core
import AppKit
import Carbon.HIToolbox

/// Global hotkey via Carbon's RegisterEventHotKey — the standard, dependency-free
/// way to get a system-wide shortcut on macOS. Default: ⌘⇧Space. Needs no TCC
/// permission.
public final class GlobalHotkeyService: HotkeyService, @unchecked Sendable {
    public let events: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    private let identifier: String
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    public init(identifier: String = "toggle-panel") {
        self.identifier = identifier
        (events, continuation) = AsyncStream.makeStream()
    }

    /// Returns false if the shortcut couldn't be registered (usually: another app
    /// already owns it). Safe to call again after `stop()`.
    @discardableResult
    public func start() -> Bool {
        // Default: ⌘⇧Space. ⌥Space / ⌃Space are often taken (input-source
        // switching, other launchers). Alternatives if this conflicts:
        //   ⌃⌥Space → UInt32(controlKey | optionKey)
        //   ⌘⌥Space → UInt32(cmdKey | optionKey)   (Finder uses this — avoid)
        guard hotKeyRef == nil else { return true }
        return register(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey))
    }

    public func stop() {
        if let handlerRef { RemoveEventHandler(handlerRef); self.handlerRef = nil }
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
    }

    private func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
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
        let registered = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard installed == noErr, registered == noErr else {
            stop()
            return false
        }
        return true
    }
}
