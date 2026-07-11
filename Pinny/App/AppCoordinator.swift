import AppKit
import Foundation

final class AppCoordinator {
    let model: AppModel

    private let preferences: PreferencesStore
    private let accessibilityManager: AccessibilityPermissionManager
    private let focusedWindowManager: FocusedWindowManager
    private let pinManager: WindowPinManager
    private let raiseManager: WindowRaiseManager
    private let hotKeyManager: HotKeyManager
    private let launchAtLoginManager: LaunchAtLoginManager
    private let notificationManager: NotificationManager
    private let backendReadinessChecker: PinningBackendReadinessChecking

    private var observers: [NSObjectProtocol] = []
    private var housekeepingTimer: Timer?
    private var lastLoggedAccessibilityTrust: Bool?
    private lazy var shortcutRouter = ShortcutActionRouter { [weak self] in
        self?.toggleCurrentWindow()
    }

    var onPinnedStateChanged: ((Bool) -> Void)?
    var onFirstLaunchNeedsPermission: (() -> Void)?

    init(
        model: AppModel,
        preferences: PreferencesStore = PreferencesStore(),
        accessibilityManager: AccessibilityPermissionManager = AccessibilityPermissionManager(),
        focusedWindowManager: FocusedWindowManager = FocusedWindowManager(),
        pinManager: WindowPinManager = WindowPinManager(levelController: YabaiWindowLevelController()),
        raiseManager: WindowRaiseManager = WindowRaiseManager(),
        hotKeyManager: HotKeyManager = HotKeyManager(),
        launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager(),
        notificationManager: NotificationManager = NotificationManager(),
        backendReadinessChecker: PinningBackendReadinessChecking = YabaiBackendReadinessChecker()
    ) {
        self.model = model
        self.preferences = preferences
        self.accessibilityManager = accessibilityManager
        self.focusedWindowManager = focusedWindowManager
        self.pinManager = pinManager
        self.raiseManager = raiseManager
        self.hotKeyManager = hotKeyManager
        self.launchAtLoginManager = launchAtLoginManager
        self.notificationManager = notificationManager
        self.backendReadinessChecker = backendReadinessChecker
    }

    func start() {
        PinnyLogger.lifecycle.info("Pinny started")
        refreshPermissionState()
        refreshBackendReadiness()
        refreshLaunchAtLoginState()
        installWorkspaceObservers()
        registerHotKey()

        housekeepingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.performHousekeeping()
        }

        if !model.isAccessibilityTrusted && !preferences.onboardingCompleted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.onFirstLaunchNeedsPermission?()
            }
        }
    }

    func toggleCurrentWindow() {
        PinnyLogger.hotKey.debug("Window toggle action routed")
        guard accessibilityManager.recheck() else {
            PinnyLogger.accessibility.notice("Window toggle blocked because Accessibility permission is missing")
            model.isAccessibilityTrusted = false
            model.isFocusedWindowPinned = false
            model.status = .accessibilityPermissionRequired
            notificationManager.show(message: "Accessibility permission required")
            return
        }

        model.isAccessibilityTrusted = true
        preferences.onboardingCompleted = true

        switch focusedWindowManager.focusedWindow(accessibilityTrusted: true) {
        case .failure(let error):
            PinnyLogger.window.error("Focused-window lookup failed: \(String(describing: error), privacy: .public)")
            let reason = error.localizedDescription
            model.isFocusedWindowPinned = false
            model.status = .unableToPin(reason)
            notificationManager.show(message: "Unable to pin this window")
        case .success(let window):
            PinnyLogger.window.debug("Focused window resolved for pid \(window.identity.processIdentifier, privacy: .public)")
            apply(pinManager.toggle(window: window))
            model.isFocusedWindowPinned = pinManager.isPinned(window: window)
        }
    }

    func requestAccessibilityPermission() {
        preferences.onboardingCompleted = true
        _ = accessibilityManager.requestPermission()
        refreshPermissionState()
        if !model.isAccessibilityTrusted {
            notificationManager.show(message: "Accessibility permission required")
        }
    }

    func raiseCurrentWindowOnce() {
        guard accessibilityManager.recheck() else {
            model.isAccessibilityTrusted = false
            model.status = .accessibilityPermissionRequired
            notificationManager.show(message: "Accessibility permission required")
            return
        }

        switch focusedWindowManager.focusedWindow(accessibilityTrusted: true) {
        case .failure(let error):
            model.status = .unableToRaise(error.localizedDescription)
            notificationManager.show(message: "Unable to raise this window")
        case .success(let window):
            switch raiseManager.raiseOnce(window: window) {
            case .success:
                model.status = .windowRaisedOnce(PinnedWindowSummary(
                    applicationName: window.applicationName,
                    windowTitle: window.title
                ))
                PinnyLogger.window.info("One-shot AXRaise fallback succeeded")
                notificationManager.show(message: "Raised once")
            case .failure(let error):
                model.status = .unableToRaise(error.localizedDescription)
                PinnyLogger.window.notice("One-shot AXRaise fallback failed: \(error.localizedDescription, privacy: .public)")
                notificationManager.show(message: "Unable to raise this window")
            }
        }
    }

    func openAccessibilitySettings() {
        preferences.onboardingCompleted = true
        _ = accessibilityManager.openSystemSettings()
    }

    func refreshVisibleState() {
        refreshPermissionState()
        refreshBackendReadiness()
        refreshLaunchAtLoginState()
        refreshFocusedPinState()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        model.launchAtLoginMessage = nil
        switch launchAtLoginManager.setEnabled(enabled) {
        case .success(let actualState):
            model.isLaunchAtLoginEnabled = actualState
        case .failure(let error):
            refreshLaunchAtLoginState()
            PinnyLogger.loginItem.error("Launch at Login update failed: \(error.localizedDescription, privacy: .public)")
            model.launchAtLoginMessage = error.localizedDescription
        }
    }

    func openLoginItemsSettings() {
        launchAtLoginManager.openSystemSettings()
    }

    func openAdvancedSetupGuide() {
        guard let url = URL(string: "https://github.com/asmvik/yabai/wiki/Disabling-System-Integrity-Protection") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func showAbout() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Pinny",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            .credits: NSAttributedString(
                string: "A native menu bar utility. Generic third-party always-on-top control uses an optional, user-configured yabai Dock scripting addition because public macOS APIs do not grant foreign-window presenter rights."
            )
        ])
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func cleanUp() {
        PinnyLogger.lifecycle.info("Pinny is cleaning up")
        housekeepingTimer?.invalidate()
        housekeepingTimer = nil
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        hotKeyManager.unregister()
        if case .failure(let error) = pinManager.cleanUpBeforeQuit() {
            PinnyLogger.window.fault("Pinny could not restore the pinned window while quitting: \(error.localizedDescription, privacy: .public)")
        }
        notificationManager.cleanUp()
    }

    private func registerHotKey() {
        let configuration = preferences.shortcutConfiguration
        let result = hotKeyManager.register(configuration: configuration) { [weak self] in
            self?.shortcutRouter.routeShortcut()
        }
        if case .failure(let error) = result {
            PinnyLogger.hotKey.error("Global shortcut registration failed: \(error.localizedDescription, privacy: .public)")
            model.shortcutRegistrationFailure = error.localizedDescription
        } else {
            PinnyLogger.hotKey.info("Global Control-Z shortcut registered")
            model.shortcutRegistrationFailure = nil
        }
    }

    private func apply(_ result: PinToggleResult) {
        switch result {
        case .pinned(let summary):
            PinnyLogger.window.info("Window pin operation succeeded")
            model.pinnedWindowSummary = summary
            model.status = .windowPinned(summary)
            notificationManager.show(message: "Pinned")
            onPinnedStateChanged?(true)
        case .unpinned:
            PinnyLogger.window.info("Window unpin operation succeeded")
            model.pinnedWindowSummary = nil
            model.status = .ready
            notificationManager.show(message: "Unpinned")
            onPinnedStateChanged?(false)
        case .unable(let error):
            PinnyLogger.window.notice("Window pin operation unavailable: \(error.localizedDescription, privacy: .public)")
            if let pinned = pinManager.pinnedWindow {
                model.pinnedWindowSummary = PinnedWindowSummary(
                    applicationName: pinned.window.applicationName,
                    windowTitle: pinned.window.title
                )
                model.status = .unableToPin(error.localizedDescription)
                onPinnedStateChanged?(true)
            } else {
                model.pinnedWindowSummary = nil
                model.status = .unableToPin(error.localizedDescription)
                onPinnedStateChanged?(false)
            }
            notificationManager.show(message: "Unable to pin this window")
        }
    }

    private func refreshPermissionState() {
        let trusted = accessibilityManager.recheck()
        if lastLoggedAccessibilityTrust != trusted {
            PinnyLogger.accessibility.info("Accessibility trusted: \(trusted, privacy: .public)")
            lastLoggedAccessibilityTrust = trusted
        }
        let wasTrusted = model.isAccessibilityTrusted
        model.isAccessibilityTrusted = trusted

        if trusted {
            preferences.onboardingCompleted = true
            if !wasTrusted || model.status == .accessibilityPermissionRequired {
                model.status = .ready
            }
        } else {
            model.status = .accessibilityPermissionRequired
        }
    }

    private func refreshLaunchAtLoginState() {
        model.isLaunchAtLoginEnabled = launchAtLoginManager.isEnabled
        if launchAtLoginManager.requiresApproval {
            model.launchAtLoginMessage = LaunchAtLoginError.requiresApproval.localizedDescription
        } else {
            model.launchAtLoginMessage = nil
        }
    }

    private func refreshBackendReadiness() {
        guard model.isAccessibilityTrusted, pinManager.pinnedWindow == nil else { return }
        let mayReplaceStatus: Bool
        switch model.status {
        case .ready, .advancedHelperRequired:
            mayReplaceStatus = true
        default:
            mayReplaceStatus = false
        }

        if let issue = backendReadinessChecker.readinessIssue() {
            if mayReplaceStatus {
                model.status = .advancedHelperRequired(issue)
            }
        } else if case .advancedHelperRequired = model.status {
            model.status = .ready
        }
    }

    private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.focusedWindowManager.recordActivatedApplication(app)
            self?.model.isFocusedWindowPinned = false
        })

        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self.pinManager.removeState(forTerminatedProcess: app.processIdentifier)
            self.synchronizePinnedPresentation()
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshPermissionState()
            self?.refreshBackendReadiness()
            self?.refreshLaunchAtLoginState()
        })
    }

    private func performHousekeeping() {
        let wasPinned = pinManager.pinnedWindow != nil
        let maintenance = pinManager.removeStaleStateIfNeeded()
        switch maintenance {
        case .reapplied:
            PinnyLogger.window.info("Pinned window sub-layer was re-applied")
        case .failed(let error):
            PinnyLogger.window.error("Pinned window maintenance failed: \(error.localizedDescription, privacy: .public)")
        case .unsupported, .healthy, .targetGone:
            break
        }
        if wasPinned && pinManager.pinnedWindow == nil {
            synchronizePinnedPresentation()
        }
        refreshPermissionState()
    }

    private func refreshFocusedPinState() {
        guard model.isAccessibilityTrusted else {
            model.isFocusedWindowPinned = false
            return
        }
        switch focusedWindowManager.focusedWindow(accessibilityTrusted: true) {
        case .success(let window):
            model.isFocusedWindowPinned = pinManager.isPinned(window: window)
        case .failure:
            model.isFocusedWindowPinned = false
        }
    }

    private func synchronizePinnedPresentation() {
        if let pinned = pinManager.pinnedWindow {
            let summary = PinnedWindowSummary(
                applicationName: pinned.window.applicationName,
                windowTitle: pinned.window.title
            )
            model.pinnedWindowSummary = summary
            model.status = .windowPinned(summary)
            onPinnedStateChanged?(true)
        } else {
            model.pinnedWindowSummary = nil
            model.isFocusedWindowPinned = false
            model.status = model.isAccessibilityTrusted ? .ready : .accessibilityPermissionRequired
            onPinnedStateChanged?(false)
        }
    }
}
