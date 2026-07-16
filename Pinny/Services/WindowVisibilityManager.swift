import AppKit
import ApplicationServices
import Foundation

enum WindowVisibilityError: Error, Equatable, LocalizedError {
    case minimizeUnsupported
    case accessibilityFailure(operation: String, error: AXError)
    case noHiddenWindows
    case targetGone

    var errorDescription: String? {
        switch self {
        case .minimizeUnsupported:
            return "This window does not allow macOS Accessibility to change its minimized state."
        case .accessibilityFailure(let operation, let error):
            return "Could not \(operation) the window (AXError \(error.rawValue))."
        case .noHiddenWindows:
            return "There is no window hidden by Pinny to restore."
        case .targetGone:
            return "The hidden window is no longer available."
        }
    }
}

protocol WindowVisibilityControlling {
    func hide(window: FocusedWindow) -> Result<Void, WindowVisibilityError>
    func show(window: FocusedWindow) -> Result<Void, WindowVisibilityError>
}

final class AccessibilityWindowVisibilityController: WindowVisibilityControlling {
    func hide(window: FocusedWindow) -> Result<Void, WindowVisibilityError> {
        setMinimized(true, for: window)
    }

    func show(window: FocusedWindow) -> Result<Void, WindowVisibilityError> {
        switch setMinimized(false, for: window) {
        case .failure(let error):
            return .failure(error)
        case .success:
            DispatchQueue.main.async { [weak self] in
                self?.bringToFront(window: window)
            }
            return .success(())
        }
    }

    private func setMinimized(
        _ minimized: Bool,
        for window: FocusedWindow
    ) -> Result<Void, WindowVisibilityError> {
        var settable = DarwinBoolean(false)
        let settableError = AXUIElementIsAttributeSettable(
            window.element,
            kAXMinimizedAttribute as CFString,
            &settable
        )
        guard settableError == .success else {
            return .failure(axFailure(
                operation: minimized ? "hide" : "restore",
                error: settableError
            ))
        }
        guard settable.boolValue else {
            return .failure(.minimizeUnsupported)
        }

        let value: CFBoolean = minimized ? kCFBooleanTrue : kCFBooleanFalse
        let setError = AXUIElementSetAttributeValue(
            window.element,
            kAXMinimizedAttribute as CFString,
            value
        )
        guard setError == .success else {
            return .failure(axFailure(
                operation: minimized ? "hide" : "restore",
                error: setError
            ))
        }
        return .success(())
    }

    private func bringToFront(window: FocusedWindow) {
        let processIdentifier = window.identity.processIdentifier
        if let application = NSRunningApplication(processIdentifier: processIdentifier) {
            _ = application.activate(options: [])
        }

        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        _ = AXUIElementSetAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            window.element
        )
        _ = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    }

    private func axFailure(
        operation: String,
        error: AXError
    ) -> WindowVisibilityError {
        if error == .invalidUIElement {
            return .targetGone
        }
        return .accessibilityFailure(operation: operation, error: error)
    }
}

final class WindowVisibilityManager {
    private let controller: WindowVisibilityControlling
    private let validityChecker: WindowValidityChecking
    private(set) var hiddenWindows: [FocusedWindow] = []

    init(
        controller: WindowVisibilityControlling = AccessibilityWindowVisibilityController(),
        validityChecker: WindowValidityChecking = AccessibilityWindowValidityChecker()
    ) {
        self.controller = controller
        self.validityChecker = validityChecker
    }

    var hiddenWindowCount: Int { hiddenWindows.count }

    func hide(window: FocusedWindow) -> Result<PinnedWindowSummary, WindowVisibilityError> {
        switch controller.hide(window: window) {
        case .success:
            hiddenWindows.removeAll { $0.identity == window.identity }
            hiddenWindows.append(window)
            return .success(summary(for: window))
        case .failure(let error):
            return .failure(error)
        }
    }

    func showLastHidden() -> Result<PinnedWindowSummary, WindowVisibilityError> {
        while let window = hiddenWindows.last {
            guard validityChecker.isValid(window: window) else {
                hiddenWindows.removeLast()
                continue
            }

            switch controller.show(window: window) {
            case .success:
                hiddenWindows.removeLast()
                return .success(summary(for: window))
            case .failure(.targetGone):
                hiddenWindows.removeLast()
            case .failure(let error):
                return .failure(error)
            }
        }
        return .failure(.noHiddenWindows)
    }

    func removeState(forTerminatedProcess processIdentifier: pid_t) {
        hiddenWindows.removeAll {
            $0.identity.processIdentifier == processIdentifier
        }
    }

    func removeStaleStateIfNeeded() {
        hiddenWindows.removeAll { !validityChecker.isValid(window: $0) }
    }

    private func summary(for window: FocusedWindow) -> PinnedWindowSummary {
        PinnedWindowSummary(
            applicationName: window.applicationName,
            windowTitle: window.title
        )
    }
}
