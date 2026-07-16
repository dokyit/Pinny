import Carbon.HIToolbox
import Foundation

enum HotKeyRegistrationError: Error, Equatable, LocalizedError {
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus, displayName: String)

    var errorDescription: String? {
        switch self {
        case .eventHandlerInstallationFailed(let status):
            return "Could not install the global shortcut handler (OSStatus \(status))."
        case .registrationFailed(let status, let displayName):
            if status == eventHotKeyExistsErr {
                return "\(displayName) is already registered by another application."
            }
            return "Could not register \(displayName) (OSStatus \(status))."
        }
    }
}

final class HotKeyManager {
    private static let signature: OSType = 0x506E6E79 // "Pnny"

    private struct Registration {
        let configuration: HotKeyConfiguration
        let reference: EventHotKeyRef
        var action: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var eventHandlerReference: EventHandlerRef?

    var isRegistered: Bool { !registrations.isEmpty }

    func register(
        identifier: PinnyHotKey,
        configuration: HotKeyConfiguration,
        action: @escaping () -> Void
    ) -> Result<Void, HotKeyRegistrationError> {
        if var existing = registrations[identifier.rawValue] {
            if existing.configuration == configuration {
                existing.action = action
                registrations[identifier.rawValue] = existing
                return .success(())
            }
            unregister(identifier: identifier)
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
            id: identifier.rawValue
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
            if registrations.isEmpty, let eventHandlerReference {
                RemoveEventHandler(eventHandlerReference)
                self.eventHandlerReference = nil
            }
            return .failure(.registrationFailed(
                registrationStatus,
                displayName: configuration.displayName
            ))
        }

        registrations[identifier.id] = Registration(
            configuration: configuration,
            reference: reference,
            action: action
        )
        return .success(())
    }

    func unregister(identifier: PinnyHotKey) {
        if let registration = registrations.removeValue(forKey: identifier.rawValue) {
            UnregisterEventHotKey(registration.reference)
        }
        removeEventHandlerIfUnused()
    }

    func unregister() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.reference)
        }
        registrations.removeAll()
        removeEventHandlerIfUnused()
    }

    private func removeEventHandlerIfUnused() {
        guard registrations.isEmpty else { return }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
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
              let registration = registrations[identifier.id] else {
            return OSStatus(eventNotHandledErr)
        }
        registration.action()
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
