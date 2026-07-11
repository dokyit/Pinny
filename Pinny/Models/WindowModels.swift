import ApplicationServices
import CoreGraphics
import Foundation

struct WindowIdentity: Hashable, CustomStringConvertible {
    let processIdentifier: pid_t
    let accessibilityElementHash: CFHashCode
    private let accessibilityElement: AXUIElement?

    init(processIdentifier: pid_t, accessibilityElementHash: CFHashCode) {
        self.processIdentifier = processIdentifier
        self.accessibilityElementHash = accessibilityElementHash
        accessibilityElement = nil
    }

    init(processIdentifier: pid_t, accessibilityElement: AXUIElement) {
        self.processIdentifier = processIdentifier
        accessibilityElementHash = CFHash(accessibilityElement)
        self.accessibilityElement = accessibilityElement
    }

    static func == (lhs: WindowIdentity, rhs: WindowIdentity) -> Bool {
        guard lhs.processIdentifier == rhs.processIdentifier else { return false }
        if let lhsElement = lhs.accessibilityElement,
           let rhsElement = rhs.accessibilityElement {
            return CFEqual(lhsElement, rhsElement)
        }
        return lhs.accessibilityElementHash == rhs.accessibilityElementHash
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(processIdentifier)
        hasher.combine(accessibilityElementHash)
    }

    var description: String {
        "pid=\(processIdentifier), ax=\(accessibilityElementHash)"
    }
}

/// A process-local reference to one specific Accessibility window element.
///
/// AXUIElement does not expose a public CGWindowID. Pinny therefore retains the
/// element and compares its CF identity while the app is running. This state is
/// deliberately never persisted across launches.
struct FocusedWindow {
    let identity: WindowIdentity
    let applicationName: String
    let applicationBundleIdentifier: String?
    let title: String?
    let role: String
    let subrole: String?
    let element: AXUIElement

    var displayName: String {
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return applicationName
        }
        return "\(applicationName) — \(title)"
    }
}

struct PinnedWindowSummary: Equatable {
    let applicationName: String
    let windowTitle: String?

    var displayName: String {
        guard let windowTitle, !windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return applicationName
        }
        return "\(applicationName) — \(windowTitle)"
    }
}

struct YabaiWindowRestorationState: Equatable {
    let ownerProcessIdentifier: pid_t
    let windowID: CGWindowID
    let originalSubLayer: String
}

struct WindowLevelToken: Equatable {
    enum Storage: Equatable {
        case opaque(String)
        case yabai(YabaiWindowRestorationState)
    }

    let storage: Storage

    init(rawValue: String) {
        storage = .opaque(rawValue)
    }

    init(yabaiState: YabaiWindowRestorationState) {
        storage = .yabai(yabaiState)
    }

    var yabaiState: YabaiWindowRestorationState? {
        guard case .yabai(let state) = storage else { return nil }
        return state
    }
}

enum WindowPinningError: Error, Equatable, LocalizedError {
    case unsupportedByPublicAPI
    case advancedHelperUnavailable(String)
    case windowIDMappingFailed(AXError)
    case targetRejected(String)
    case accessibilityFailure(AXError)
    case staleWindow
    case ownerMismatch(expected: pid_t, actual: pid_t)
    case verificationFailed(expected: String, actual: String?)
    case restorationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedByPublicAPI:
            return "macOS does not expose a public API for changing another app's window level."
        case .advancedHelperUnavailable(let reason):
            return reason
        case .windowIDMappingFailed(let error):
            return "The focused window could not be mapped to a WindowServer ID (AXError \(error.rawValue))."
        case .targetRejected(let reason):
            return reason
        case .accessibilityFailure(let error):
            return "Accessibility returned error \(error.rawValue)."
        case .staleWindow:
            return "The selected window is no longer available."
        case .ownerMismatch(let expected, let actual):
            return "The WindowServer owner changed (expected PID \(expected), got \(actual)); Pinny refused to affect a different window."
        case .verificationFailed(let expected, let actual):
            let observed = actual ?? "no window"
            return "Window level verification failed (expected \(expected), got \(observed))."
        case .restorationFailed(let reason):
            return reason
        }
    }
}

enum PinToggleResult: Equatable {
    case pinned(PinnedWindowSummary)
    case unpinned
    case unable(WindowPinningError)
}
