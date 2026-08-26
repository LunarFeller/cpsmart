import Carbon
import Foundation

final class GlobalHotKey {
    private static var nextIdentifier: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let identifier: UInt32
    private let action: () -> Void

    let gesture: ShortcutGesture

    init?(gesture: ShortcutGesture, action: @escaping () -> Void) {
        identifier = Self.nextIdentifier
        Self.nextIdentifier &+= 1
        self.gesture = gesture
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                let instance = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                guard status == noErr,
                      hotKeyID.signature == GlobalHotKey.signature,
                      hotKeyID.id == instance.identifier else {
                    return OSStatus(eventNotHandledErr)
                }
                instance.action()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        let registerStatus = RegisterEventHotKey(
            UInt32(gesture.keyCode),
            gesture.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
            }
            return nil
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private static let signature: OSType = 0x434C4950 // "CLIP"
}
