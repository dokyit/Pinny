import ApplicationServices
import Foundation

/// Implements the closest supported fallback to always-on-top behavior.
/// AXRaise is intentionally one-shot and never changes Pinny's pinned state.
final class WindowRaiseManager {
    func raiseOnce(window: FocusedWindow) -> Result<Void, WindowPinningError> {
        var actionsValue: CFArray?
        let actionsError = AXUIElementCopyActionNames(window.element, &actionsValue)
        guard actionsError == .success else {
            return .failure(.accessibilityFailure(actionsError))
        }

        let actions = (actionsValue as? [String]) ?? []
        guard actions.contains(kAXRaiseAction as String) else {
            return .failure(.targetRejected("This window does not expose the one-shot AXRaise action."))
        }

        let error = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        guard error == .success else {
            return .failure(.accessibilityFailure(error))
        }
        return .success(())
    }
}
