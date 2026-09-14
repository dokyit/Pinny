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
        isFocusedWindowPinned: Bool? = nil,
        previewState: WindowPreviewState? = nil
    ) -> MenuPresentation {
        if let previewState {
            return makePreviewPresentation(
                status: status,
                previewState: previewState,
                shortcutRegistrationFailure: shortcutRegistrationFailure
            )
        }
        return makeLegacyPresentation(
            status: status,
            isAccessibilityTrusted: isAccessibilityTrusted,
            shortcutRegistrationFailure: shortcutRegistrationFailure,
            isFocusedWindowPinned: isFocusedWindowPinned
        )
    }

    private static func makePreviewPresentation(
        status: AppStatus,
        previewState: WindowPreviewState,
        shortcutRegistrationFailure: String?
    ) -> MenuPresentation {
        let statusTitle: String
        let actionTitle: String
        var detailParts: [String] = []

        switch previewState {
        case .idle:
            actionTitle = "Float Window Preview"
            switch status {
            case .windowHidden(let window):
                statusTitle = "Window hidden"
                detailParts.append("Hidden: \(window.displayName)")
            case .windowShown(let window):
                statusTitle = "Window restored"
                detailParts.append("Restored: \(window.displayName)")
            case .windowRaisedOnce(let window):
                statusTitle = "Raised once"
                detailParts.append("\(window.displayName) was raised once and may be covered again.")
            case .unableToRaise(let reason):
                statusTitle = "Unable to raise this window"
                detailParts.append(reason)
            case .unableToHide(let reason):
                statusTitle = "Unable to hide this window"
                detailParts.append(reason)
            case .unableToShow(let reason):
                statusTitle = "Unable to restore a window"
                detailParts.append(reason)
            case .shortcutRegistrationFailed(let reason):
                statusTitle = "Shortcut registration failed"
                detailParts.append(reason)
            case .ready, .windowPinned, .advancedHelperRequired,
                 .accessibilityPermissionRequired, .unableToPin:
                statusTitle = "Ready"
            }
        case .loading:
            statusTitle = "Finding windows…"
            actionTitle = "Cancel Preview"
        case .choosing:
            statusTitle = "Choose a window"
            actionTitle = "Cancel Preview"
        case .starting:
            statusTitle = "Starting preview…"
            actionTitle = "Cancel Preview"
        case .active(let window):
            statusTitle = "Live preview"
            actionTitle = "Close Preview"
            detailParts.append("\(window.summary.displayName) — View only")
        case .failed(let reason):
            statusTitle = "Unable to show preview"
            actionTitle = "Float Window Preview"
            detailParts.append(reason)
        }

        if previewState != .idle {
            switch status {
            case .unableToHide(let reason), .unableToShow(let reason),
                 .unableToRaise(let reason), .shortcutRegistrationFailed(let reason):
                detailParts.append(reason)
            default:
                break
            }
        }

        if let shortcutRegistrationFailure,
           !shortcutRegistrationFailure.isEmpty,
           !detailParts.contains(shortcutRegistrationFailure) {
            detailParts.append(shortcutRegistrationFailure)
        }

        return MenuPresentation(
            statusTitle: statusTitle,
            statusDetail: detailParts.isEmpty ? nil : detailParts.joined(separator: "\n"),
            actionTitle: actionTitle,
            canToggleWindow: true
        )
    }

    private static func makeLegacyPresentation(
        status: AppStatus,
        isAccessibilityTrusted: Bool,
        shortcutRegistrationFailure: String?,
        isFocusedWindowPinned: Bool?
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
