import Foundation

enum UnsupportedWindowFilter {
    private static let blockedBundleIdentifiers: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.notificationcenterui",
        "com.apple.systemuiserver",
        "com.apple.WindowManager"
    ]

    private static let blockedApplicationNames: Set<String> = [
        "Control Center",
        "Dock",
        "Notification Center",
        "SystemUIServer",
        "WindowManager"
    ]

    private static let supportedRoles: Set<String> = [
        "AXWindow",
        "AXSheet"
    ]

    static func rejectionReason(
        bundleIdentifier: String?,
        applicationName: String,
        role: String
    ) -> String? {
        if let bundleIdentifier, blockedBundleIdentifiers.contains(bundleIdentifier) {
            return "Pinny does not control protected macOS system UI."
        }
        if blockedApplicationNames.contains(applicationName) {
            return "Pinny does not control protected macOS system UI."
        }
        guard supportedRoles.contains(role) else {
            return "The focused Accessibility element is not an application window."
        }
        return nil
    }
}
