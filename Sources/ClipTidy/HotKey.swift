import AppKit
import Carbon.HIToolbox

/// Registers system-wide keyboard shortcuts using Carbon's RegisterEventHotKey.
/// This works from a menu bar app without Accessibility permissions, so the
/// shortcuts fire no matter which app is focused or whether the menu bar icon
/// is reachable.
final class HotKeyCenter {

    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    private init() {}

    /// Carbon modifier masks, for readability at call sites.
    struct Modifiers {
        static let command = UInt32(cmdKey)
        static let option  = UInt32(optionKey)
        static let control = UInt32(controlKey)
        static let shift   = UInt32(shiftKey)
    }

    /// Registers a global shortcut. `keyCode` is a Carbon virtual key code
    /// (for example `kVK_ANSI_C`). `modifiers` is an OR of `Modifiers` values.
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1
        handlers[id] = handler

        let hotKeyID = EventHotKeyID(signature: fourCharCode("CTDY"), id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            refs.append(ref)
        } else {
            handlers[id] = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                HotKeyCenter.shared.handlers[hkID.id]?()
                return noErr
            },
            1,
            &spec,
            nil,
            nil
        )
    }

    private func fourCharCode(_ string: String) -> FourCharCode {
        var result: FourCharCode = 0
        for char in string.utf16 {
            result = (result << 8) + FourCharCode(char)
        }
        return result
    }
}
