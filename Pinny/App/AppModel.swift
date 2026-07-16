import Combine
import Foundation

final class AppModel: ObservableObject {
    @Published var status: AppStatus = .ready
    @Published var isAccessibilityTrusted = false
    @Published var isLaunchAtLoginEnabled = false
    @Published var launchAtLoginMessage: String?
    @Published var shortcutRegistrationFailure: String?
    @Published var pinnedWindowSummary: PinnedWindowSummary?
    @Published var isFocusedWindowPinned = false
    @Published var hiddenWindowCount = 0

    let shortcutDisplayName: String

    init(shortcutDisplayName: String = HotKeyConfiguration.controlZ.displayName) {
        self.shortcutDisplayName = shortcutDisplayName
    }

    var menuPresentation: MenuPresentation {
        return MenuPresentation.make(
            status: status,
            isAccessibilityTrusted: isAccessibilityTrusted,
            shortcutRegistrationFailure: shortcutRegistrationFailure,
            isFocusedWindowPinned: isFocusedWindowPinned
        )
    }

    var hasPinnedWindow: Bool {
        pinnedWindowSummary != nil
    }

    var hasHiddenWindows: Bool {
        hiddenWindowCount > 0
    }
}
