import Carbon.HIToolbox
import Foundation

enum HotKeyRegistrationError: Error, Equatable, LocalizedError {
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .eventHandlerInstallationFailed(let status):
            return "Could not install the global shortcut handler (OSStatus \(status))."
        case .registrationFailed(let status):
            if status == eventHotKeyExistsErr {
                return "⌃Z is already registered by another application."
            }
            return "Could not register ⌃Z (OSStatus \(status))."
        }
    }
}

final class HotKeyManager {
    private static let signature: OSType = 0x506E6E79 // "Pnny"
    private static let identifier: UInt32 = 1

    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private var action: (() -> Void)?
    private(set) var configuration: HotKeyConfiguration?

    var isRegistered: Bool { hotKeyReference != nil }

    func register(
        configuration: HotKeyConfiguration,
        action: @escaping () -> Void
    ) -> Result<Void, HotKeyRegistrationError> {
        if isRegistered {
            if self.configuration == configuration {
                self.action = action
                return .success(())
            }
            unregister()
        }

        if eventHandlerReference == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let installStatus = InstallEventHandler(
                GetApplicationEventTarget(),
                pinnyHotKeyEventHandler,
                1,
                &eventType,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                &eventHandlerReference
            )
            guard installStatus == noErr else {
                eventHandlerReference = nil
                return .failure(.eventHandlerInstallationFailed(installStatus))
            }
        }

        let identifier = EventHotKeyID(
            signature: Self.signature,
            id: Self.identifier
        )
        var reference: EventHotKeyRef?
        let registrationStatus = RegisterEventHotKey(
            configuration.keyCode,
            configuration.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &reference
        )
        guard registrationStatus == noErr, let reference else {
            if let eventHandlerReference {
                RemoveEventHandler(eventHandlerReference)
                self.eventHandlerReference = nil
            }
            return .failure(.registrationFailed(registrationStatus))
        }

        self.configuration = configuration
        self.action = action
        hotKeyReference = reference
        return .success(())
    }

    func unregister() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
        configuration = nil
        action = nil
    }

    fileprivate func handle(event: EventRef?) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }
        var identifier = EventHotKeyID()
        let parameterStatus = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier
        )
        guard parameterStatus == noErr,
              identifier.signature == Self.signature,
              identifier.id == Self.identifier else {
            return OSStatus(eventNotHandledErr)
        }
        action?()
        return noErr
    }

    deinit {
        unregister()
    }
}

private let pinnyHotKeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    return manager.handle(event: event)
}
