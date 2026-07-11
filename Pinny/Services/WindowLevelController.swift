import ApplicationServices
import Foundation

enum WindowLevelMaintenanceResult: Equatable {
    case unsupported
    case healthy
    case reapplied
    case targetGone
    case failed(WindowPinningError)
}

protocol WindowLevelControlling: AnyObject {
    func pin(window: FocusedWindow) -> Result<WindowLevelToken, WindowPinningError>
    func unpin(window: FocusedWindow, token: WindowLevelToken) -> Result<Void, WindowPinningError>
    func representsSameWindow(
        candidate: FocusedWindow,
        pinnedWindow: FocusedWindow,
        token: WindowLevelToken
    ) -> Bool
    func maintain(window: FocusedWindow, token: WindowLevelToken) -> WindowLevelMaintenanceResult
}

extension WindowLevelControlling {
    func representsSameWindow(
        candidate: FocusedWindow,
        pinnedWindow: FocusedWindow,
        token: WindowLevelToken
    ) -> Bool {
        candidate.identity == pinnedWindow.identity
    }

    func maintain(window: FocusedWindow, token: WindowLevelToken) -> WindowLevelMaintenanceResult {
        .unsupported
    }
}

/// The supported public-API implementation.
///
/// AppKit's `NSWindow.level` only applies to windows owned by this process.
/// Accessibility exposes moving, resizing, minimizing, and AXRaise, but no
/// attribute that changes another process's persistent window level. Core
/// Graphics window-list APIs are observational. Returning failure here is
/// intentional: a failed operation must never enter Pinny's pinned state.
final class PublicWindowLevelController: WindowLevelControlling {
    func pin(window: FocusedWindow) -> Result<WindowLevelToken, WindowPinningError> {
        .failure(.unsupportedByPublicAPI)
    }

    func unpin(window: FocusedWindow, token: WindowLevelToken) -> Result<Void, WindowPinningError> {
        .failure(.unsupportedByPublicAPI)
    }

    func diagnosticReport(for window: FocusedWindow) -> WindowPinningDiagnostic {
        var names: CFArray?
        let attributesError = AXUIElementCopyAttributeNames(window.element, &names)

        var actions: CFArray?
        let actionsError = AXUIElementCopyActionNames(window.element, &actions)

        let attributeNames = (names as? [String]) ?? []
        let actionNames = (actions as? [String]) ?? []

        return WindowPinningDiagnostic(
            attributesError: attributesError,
            actionNamesError: actionsError,
            exposesRaiseAction: actionNames.contains(kAXRaiseAction as String),
            exposesPublicWindowLevelAttribute: attributeNames.contains(where: {
                $0.localizedCaseInsensitiveContains("windowlevel") ||
                    $0.localizedCaseInsensitiveContains("alwaysontop")
            })
        )
    }
}

/// Verified generic backend for machines where the user has independently
/// installed and enabled yabai's privileged Dock scripting addition.
///
/// Pinny does not weaken System Integrity Protection, install yabai, or inject
/// code itself. It uses yabai's narrow message interface, then independently
/// queries the resulting compositor-derived sub-layer before reporting success.
final class YabaiWindowLevelController: WindowLevelControlling {
    private let service: YabaiWindowServicing

    init(service: YabaiWindowServicing = YabaiWindowService()) {
        self.service = service
    }

    func pin(window: FocusedWindow) -> Result<WindowLevelToken, WindowPinningError> {
        let windowID: CGWindowID
        switch service.windowID(for: window.element) {
        case .success(let identifier):
            windowID = identifier
        case .failure(let error):
            return .failure(error)
        }

        let original: YabaiWindowRecord
        switch service.windowRecord(for: windowID) {
        case .success(let record):
            original = record
        case .failure(let error):
            return .failure(error)
        }

        guard original.ownerProcessIdentifier == window.identity.processIdentifier else {
            return .failure(.ownerMismatch(
                expected: window.identity.processIdentifier,
                actual: original.ownerProcessIdentifier
            ))
        }
        guard ["above", "normal", "below"].contains(original.subLayer) else {
            return .failure(.targetRejected(
                "yabai reported an unknown original sub-layer; Pinny cannot restore it safely."
            ))
        }

        let restorationState = YabaiWindowRestorationState(
            ownerProcessIdentifier: original.ownerProcessIdentifier,
            windowID: windowID,
            originalSubLayer: original.subLayer
        )

        switch service.setSubLayer("above", for: windowID) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        switch verifiedRecord(
            windowID: windowID,
            expectedOwner: original.ownerProcessIdentifier,
            expectedSubLayer: "above"
        ) {
        case .success:
            return .success(WindowLevelToken(yabaiState: restorationState))
        case .failure(let verificationError):
            let restoration = restore(state: restorationState)
            if case .failure(let restorationError) = restoration {
                return .failure(.restorationFailed(
                    "Pin verification failed and the original sub-layer could not be restored: \(restorationError.localizedDescription)"
                ))
            }
            return .failure(verificationError)
        }
    }

    func unpin(
        window: FocusedWindow,
        token: WindowLevelToken
    ) -> Result<Void, WindowPinningError> {
        guard let state = token.yabaiState else {
            return .failure(.restorationFailed("The window restoration token is invalid."))
        }
        guard state.ownerProcessIdentifier == window.identity.processIdentifier else {
            return .failure(.restorationFailed(
                "The pinned window owner no longer matches its restoration token."
            ))
        }
        return restore(state: state)
    }

    func representsSameWindow(
        candidate: FocusedWindow,
        pinnedWindow: FocusedWindow,
        token: WindowLevelToken
    ) -> Bool {
        guard let state = token.yabaiState,
              state.ownerProcessIdentifier == candidate.identity.processIdentifier else {
            return false
        }

        guard case .success(let candidateWindowID) = service.windowID(for: candidate.element) else {
            return false
        }
        return candidateWindowID == state.windowID
    }

    func maintain(
        window: FocusedWindow,
        token: WindowLevelToken
    ) -> WindowLevelMaintenanceResult {
        guard let state = token.yabaiState else {
            return .failed(.restorationFailed("The window restoration token is invalid."))
        }

        let record: YabaiWindowRecord
        switch service.windowRecord(for: state.windowID) {
        case .failure(.staleWindow):
            return .targetGone
        case .failure(let error):
            return .failed(error)
        case .success(let current):
            record = current
        }

        guard record.ownerProcessIdentifier == state.ownerProcessIdentifier else {
            // The original target is gone and its numeric ID has been recycled.
            // Never touch the new owner's window.
            return .targetGone
        }
        guard record.subLayer != "above" else {
            return .healthy
        }

        switch service.setSubLayer("above", for: state.windowID) {
        case .failure(let error):
            return .failed(error)
        case .success:
            break
        }

        switch verifiedRecord(
            windowID: state.windowID,
            expectedOwner: state.ownerProcessIdentifier,
            expectedSubLayer: "above"
        ) {
        case .success:
            return .reapplied
        case .failure(let error):
            return .failed(error)
        }
    }

    private func restore(
        state: YabaiWindowRestorationState
    ) -> Result<Void, WindowPinningError> {
        let current: YabaiWindowRecord
        switch service.windowRecord(for: state.windowID) {
        case .failure(.staleWindow):
            return .success(())
        case .failure(let error):
            return .failure(error)
        case .success(let record):
            current = record
        }

        guard current.ownerProcessIdentifier == state.ownerProcessIdentifier else {
            return .failure(.ownerMismatch(
                expected: state.ownerProcessIdentifier,
                actual: current.ownerProcessIdentifier
            ))
        }
        guard current.subLayer != state.originalSubLayer else {
            return .success(())
        }

        var lastFailure: WindowPinningError?
        for _ in 0..<2 {
            switch service.setSubLayer(state.originalSubLayer, for: state.windowID) {
            case .failure(let error):
                lastFailure = error
                continue
            case .success:
                break
            }

            switch verifiedRecord(
                windowID: state.windowID,
                expectedOwner: state.ownerProcessIdentifier,
                expectedSubLayer: state.originalSubLayer
            ) {
            case .success:
                return .success(())
            case .failure(let error):
                lastFailure = error
            }
        }

        return .failure(.restorationFailed(
            lastFailure?.localizedDescription ?? "The original window sub-layer could not be restored."
        ))
    }

    private func verifiedRecord(
        windowID: CGWindowID,
        expectedOwner: pid_t,
        expectedSubLayer: String
    ) -> Result<Void, WindowPinningError> {
        switch service.windowRecord(for: windowID) {
        case .failure(let error):
            return .failure(error)
        case .success(let record):
            guard record.ownerProcessIdentifier == expectedOwner else {
                return .failure(.ownerMismatch(
                    expected: expectedOwner,
                    actual: record.ownerProcessIdentifier
                ))
            }
            guard record.subLayer == expectedSubLayer else {
                return .failure(.verificationFailed(
                    expected: expectedSubLayer,
                    actual: record.subLayer
                ))
            }
            return .success(())
        }
    }
}

struct WindowPinningDiagnostic: Equatable {
    let attributesError: AXError
    let actionNamesError: AXError
    let exposesRaiseAction: Bool
    let exposesPublicWindowLevelAttribute: Bool
}
