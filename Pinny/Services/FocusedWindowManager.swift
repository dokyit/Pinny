import AppKit
import ApplicationServices
import Foundation

enum FocusedWindowError: Error, Equatable, LocalizedError {
    case accessibilityPermissionRequired
    case noFocusedApplication
    case pinnyIsFrontmost
    case unsupportedTarget(String)
    case noFocusedWindow(AXError)
    case invalidWindowElement

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "Accessibility permission is required."
        case .noFocusedApplication:
            return "No focused application was found."
        case .pinnyIsFrontmost:
            return "Choose another application's window first."
        case .unsupportedTarget(let reason):
            return reason
        case .noFocusedWindow:
            return "The active application does not expose a focused window."
        case .invalidWindowElement:
            return "The focused Accessibility element is no longer valid."
        }
    }
}

final class FocusedWindowManager {
    private let ownProcessIdentifier: pid_t
    private var lastExternalApplication: NSRunningApplication?

    init(ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.ownProcessIdentifier = ownProcessIdentifier
        recordActivatedApplication(NSWorkspace.shared.frontmostApplication)
    }

    func recordActivatedApplication(_ application: NSRunningApplication?) {
        guard let application, application.processIdentifier != ownProcessIdentifier else { return }
        lastExternalApplication = application
    }

    func focusedWindow(accessibilityTrusted: Bool) -> Result<FocusedWindow, FocusedWindowError> {
        guard accessibilityTrusted else {
            return .failure(.accessibilityPermissionRequired)
        }

        let frontmost = NSWorkspace.shared.frontmostApplication
        let application: NSRunningApplication?
        if frontmost?.processIdentifier == ownProcessIdentifier {
            application = lastExternalApplication
        } else {
            application = frontmost
            recordActivatedApplication(frontmost)
        }

        guard let application else {
            return .failure(.noFocusedApplication)
        }
        guard application.processIdentifier != ownProcessIdentifier else {
            return .failure(.pinnyIsFrontmost)
        }

        let appName = application.localizedName ?? "Unknown Application"
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var focusedValue: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedValue
        )

        guard focusedError == .success, let focusedValue else {
            return .failure(.noFocusedWindow(focusedError))
        }
        guard CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return .failure(.invalidWindowElement)
        }

        let window = unsafeBitCast(focusedValue, to: AXUIElement.self)
        let role = stringAttribute(kAXRoleAttribute as CFString, element: window) ?? ""
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, element: window)

        if let reason = UnsupportedWindowFilter.rejectionReason(
            bundleIdentifier: application.bundleIdentifier,
            applicationName: appName,
            role: role
        ) {
            return .failure(.unsupportedTarget(reason))
        }

        var elementPID: pid_t = 0
        let pidError = AXUIElementGetPid(window, &elementPID)
        guard pidError == .success, elementPID == application.processIdentifier else {
            return .failure(.invalidWindowElement)
        }

        return .success(FocusedWindow(
            identity: WindowIdentity(
                processIdentifier: elementPID,
                accessibilityElement: window
            ),
            applicationName: appName,
            applicationBundleIdentifier: application.bundleIdentifier,
            title: stringAttribute(kAXTitleAttribute as CFString, element: window),
            role: role,
            subrole: subrole,
            element: window
        ))
    }

    private func stringAttribute(_ attribute: CFString, element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
