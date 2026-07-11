import ApplicationServices
import Foundation

protocol WindowValidityChecking {
    func isValid(window: FocusedWindow) -> Bool
}

struct AccessibilityWindowValidityChecker: WindowValidityChecking {
    func isValid(window: FocusedWindow) -> Bool {
        var role: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            window.element,
            kAXRoleAttribute as CFString,
            &role
        )
        if error == .success {
            return role != nil
        }
        // A temporarily unresponsive application can return cannotComplete.
        // Retain state so Pinny can still restore it after the app recovers.
        return error != .invalidUIElement
    }
}

final class WindowPinManager {
    struct PinnedWindow {
        let window: FocusedWindow
        let restorationToken: WindowLevelToken
    }

    private let levelController: WindowLevelControlling
    private let validityChecker: WindowValidityChecking
    private(set) var pinnedWindow: PinnedWindow?

    init(
        levelController: WindowLevelControlling,
        validityChecker: WindowValidityChecking = AccessibilityWindowValidityChecker()
    ) {
        self.levelController = levelController
        self.validityChecker = validityChecker
    }

    func toggle(window: FocusedWindow) -> PinToggleResult {
        removeStaleStateIfNeeded()

        if let current = pinnedWindow,
           levelController.representsSameWindow(
               candidate: window,
               pinnedWindow: current.window,
               token: current.restorationToken
           ) {
            switch levelController.unpin(window: current.window, token: current.restorationToken) {
            case .success:
                pinnedWindow = nil
                return .unpinned
            case .failure(let error):
                return .unable(error)
            }
        }

        if let current = pinnedWindow {
            switch levelController.unpin(window: current.window, token: current.restorationToken) {
            case .success:
                pinnedWindow = nil
            case .failure(let error):
                return .unable(error)
            }
        }

        switch levelController.pin(window: window) {
        case .success(let token):
            pinnedWindow = PinnedWindow(window: window, restorationToken: token)
            return .pinned(PinnedWindowSummary(
                applicationName: window.applicationName,
                windowTitle: window.title
            ))
        case .failure(let error):
            return .unable(error)
        }
    }

    func removeState(forTerminatedProcess processIdentifier: pid_t) {
        guard pinnedWindow?.window.identity.processIdentifier == processIdentifier else { return }
        pinnedWindow = nil
    }

    func isPinned(window: FocusedWindow) -> Bool {
        guard let current = pinnedWindow else { return false }
        return levelController.representsSameWindow(
            candidate: window,
            pinnedWindow: current.window,
            token: current.restorationToken
        )
    }

    @discardableResult
    func removeStaleStateIfNeeded() -> WindowLevelMaintenanceResult {
        guard let current = pinnedWindow else { return .unsupported }
        if !validityChecker.isValid(window: current.window) {
            // An invalid retained AX element means the original window is gone.
            // Do not use a potentially recycled numeric WindowServer ID.
            pinnedWindow = nil
            return .targetGone
        }

        let maintenance = levelController.maintain(
            window: current.window,
            token: current.restorationToken
        )
        switch maintenance {
        case .healthy, .reapplied, .failed:
            return maintenance
        case .targetGone:
            pinnedWindow = nil
            return .targetGone
        case .unsupported:
            return .healthy
        }
    }

    @discardableResult
    func cleanUpBeforeQuit() -> Result<Void, WindowPinningError> {
        guard let current = pinnedWindow else { return .success(()) }
        let result = levelController.unpin(
            window: current.window,
            token: current.restorationToken
        )
        if case .success = result {
            pinnedWindow = nil
        }
        return result
    }
}
