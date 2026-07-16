import Foundation

enum AppStatus: Equatable {
    case ready
    case windowPinned(PinnedWindowSummary)
    case windowRaisedOnce(PinnedWindowSummary)
    case windowHidden(PinnedWindowSummary)
    case windowShown(PinnedWindowSummary)
    case accessibilityPermissionRequired
    case advancedHelperRequired(String)
    case unableToPin(String)
    case unableToRaise(String)
    case unableToHide(String)
    case unableToShow(String)
    case shortcutRegistrationFailed(String)
}

struct MenuPresentation: Equatable {
    let statusTitle: String
    let statusDetail: String?
    let actionTitle: String
    let canToggleWindow: Bool

    static func make(
        status: AppStatus,
        isAccessibilityTrusted: Bool,
        shortcutRegistrationFailure: String? = nil,
        isFocusedWindowPinned: Bool? = nil
    ) -> MenuPresentation {
        let statusRepresentsPinnedWindow: Bool
        if case .windowPinned = status {
            statusRepresentsPinnedWindow = true
        } else {
            statusRepresentsPinnedWindow = false
        }
        let actionTitle = (isFocusedWindowPinned ?? statusRepresentsPinnedWindow)
            ? "Unpin Current Window"
            : "Pin Current Window"

        guard isAccessibilityTrusted else {
            return MenuPresentation(
                statusTitle: "Accessibility permission required",
                statusDetail: "Pinny needs permission to identify the focused window.",
                actionTitle: "Pin Current Window",
                canToggleWindow: false
            )
        }

        if let shortcutRegistrationFailure {
            return MenuPresentation(
                statusTitle: "Shortcut registration failed",
                statusDetail: shortcutRegistrationFailure,
                actionTitle: actionTitle,
                canToggleWindow: true
            )
        }

        switch status {
        case .ready:
            return MenuPresentation(
                statusTitle: "Ready",
                statusDetail: nil,
                actionTitle: actionTitle,
                canToggleWindow: true
            )
        case .windowPinned(let window):
            return MenuPresentation(
                statusTitle: "Window pinned",
                statusDetail: "Pinned: \(window.displayName)",
                actionTitle: actionTitle,
                canToggleWindow: true
            )
        case .windowRaisedOnce(let window):
            return MenuPresentation(
                statusTitle: "Raised once (fallback)",
                statusDetail: "\(window.displayName) was raised once. It is not pinned and may be covered again.",
                actionTitle: actionTitle,
                canToggleWindow: true
            )
        case .windowHidden(let window):
            return MenuPresentation(
                statusTitle: "Window hidden",
                statusDetail: "Hidden: \(window.displayName)",
                actionTitle: actionTitle,
                canToggleWindow: true
            )
        case .windowShown(let window):
            return MenuPresentation(
                statusTitle: "Window restored",
                statusDetail: "Restored: \(window.displayName)",
                actionTitle: actionTitle,
                canToggleWindow: true
            )
        case .accessibilityPermissionRequired:
            return MenuPresentation(
                statusTitle: "Accessibility permission required",
                statusDetail: "Pinny needs permission to identify the focused window.",
                actionTitle: "Pin Current Window",
                canToggleWindow: false
            )
        case .advancedHelperRequired(let reason):
            return MenuPresentation(
                statusTitle: "Advanced helper required",
                statusDetail: reason,
                actionTitle: actionTitle,
                canToggleWindow: true
            )
        case .unableToPin(let reason):
            return MenuPresentation(
                statusTitle: "Unable to pin this window",
                statusDetail: reason,
                actionTitle: actionTitle,
                canToggleWindow: true
            )
        case .unableToRaise(let reason):
            return MenuPresentation(
                statusTitle: "Unable to raise this window",
                statusDetail: reason,
                actionTitle: actionTitle,
                canToggleWindow: true
            )
        case .unableToHide(let reason):
            return MenuPresentation(
                statusTitle: "Unable to hide this window",
                statusDetail: reason,
                actionTitle: actionTitle,
                canToggleWindow: true
            )
        case .unableToShow(let reason):
            return MenuPresentation(
                statusTitle: "Unable to restore a window",
                statusDetail: reason,
                actionTitle: actionTitle,
                canToggleWindow: true
            )
        case .shortcutRegistrationFailed(let reason):
            return MenuPresentation(
                statusTitle: "Shortcut registration failed",
                statusDetail: reason,
                actionTitle: actionTitle,
                canToggleWindow: true
            )
        }
    }
}
