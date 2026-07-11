import AppKit
import ApplicationServices
import Foundation

final class AccessibilityPermissionManager {
    private(set) var isTrusted: Bool

    init() {
        isTrusted = AXIsProcessTrusted()
    }

    @discardableResult
    func recheck() -> Bool {
        isTrusted = AXIsProcessTrusted()
        return isTrusted
    }

    /// Requests the standard asynchronous macOS Accessibility prompt.
    /// The return value is the current state; granting permission happens later.
    @discardableResult
    func requestPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        return isTrusted
    }

    @discardableResult
    func openSystemSettings() -> Bool {
        // Apple has no public API dedicated to opening this pane. This stable
        // System Settings URL is best-effort; opening Settings itself is the fallback.
        let candidateURLs = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for value in candidateURLs {
            if let privacyURL = URL(string: value), NSWorkspace.shared.open(privacyURL) {
                return true
            }
        }

        let settingsURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        return NSWorkspace.shared.open(settingsURL)
    }
}
