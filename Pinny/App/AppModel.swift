import Combine
import Foundation

final class AppModel: ObservableObject {
    @Published var status: AppStatus = .ready
    @Published var isAccessibilityTrusted = false
    @Published var isLaunchAtLoginEnabled = false
    @Published var launchAtLoginMessage: String?
    @Published var shortcutRegistrationFailure: String?
    @Published var previewState: WindowPreviewState = .idle
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
            previewState: previewState
        )
    }

    var hasPreview: Bool {
        previewState.activeWindow != nil
    }

    var hasHiddenWindows: Bool {
        hiddenWindowCount > 0
    }
}
