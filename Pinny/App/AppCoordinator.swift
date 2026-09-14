import AppKit
import Foundation

@MainActor
final class AppCoordinator {
    let model: AppModel

    private let preferences: PreferencesStore
    private let accessibilityManager: AccessibilityPermissionManager
    private let focusedWindowManager: FocusedWindowManager
    private let previewManager: WindowPreviewManager
    private let raiseManager: WindowRaiseManager
    private let visibilityManager: WindowVisibilityManager
    private let hotKeyManager: HotKeyManager
    private let launchAtLoginManager: LaunchAtLoginManager
    private let notificationManager: NotificationManager

    private var observers: [NSObjectProtocol] = []
    private var housekeepingTimer: Timer?
    private var lastLoggedAccessibilityTrust: Bool?
    private lazy var shortcutRouter = ShortcutActionRouter(
        toggleAction: { [weak self] in self?.toggleCurrentWindow() },
        hideAction: { [weak self] in self?.hideCurrentWindow() },
        showAction: { [weak self] in self?.showLastHiddenWindow() }
    )

    var onPinnedStateChanged: ((Bool) -> Void)?
    var onPreviewNeedsAttention: (() -> Void)?
    var onFirstLaunchNeedsPermission: (() -> Void)?

    init(
        model: AppModel,
        preferences: PreferencesStore = PreferencesStore(),
        accessibilityManager: AccessibilityPermissionManager = AccessibilityPermissionManager(),
        focusedWindowManager: FocusedWindowManager = FocusedWindowManager(),
        previewManager: WindowPreviewManager,
        raiseManager: WindowRaiseManager = WindowRaiseManager(),
        visibilityManager: WindowVisibilityManager = WindowVisibilityManager(),
        hotKeyManager: HotKeyManager = HotKeyManager(),
        launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager(),
        notificationManager: NotificationManager = NotificationManager()
    ) {
        self.model = model
        self.preferences = preferences
        self.accessibilityManager = accessibilityManager
        self.focusedWindowManager = focusedWindowManager
        self.previewManager = previewManager
        self.raiseManager = raiseManager
        self.visibilityManager = visibilityManager
        self.hotKeyManager = hotKeyManager
        self.launchAtLoginManager = launchAtLoginManager
        self.notificationManager = notificationManager
    }

    func start() {
        PinnyLogger.lifecycle.info("Pinny started")
        previewManager.onStateChange = { [weak self] state in
            self?.handlePreviewStateChange(state)
        }
        refreshPermissionState()
        refreshLaunchAtLoginState()
        installWorkspaceObservers()
        registerHotKeys()

        housekeepingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.performHousekeeping()
            }
        }

        if !model.isAccessibilityTrusted && !preferences.onboardingCompleted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                MainActor.assumeIsolated {
                    self?.onFirstLaunchNeedsPermission?()
                }
            }
        }
    }

    func toggleCurrentWindow() {
        PinnyLogger.hotKey.debug("Window toggle action routed")
        if previewManager.state.canStop {
            previewManager.stop()
            return
        }

        let trusted = accessibilityManager.recheck()
        model.isAccessibilityTrusted = trusted
        if trusted {
            preferences.onboardingCompleted = true
        }

        var selection: PreviewWindowSelection?
        if trusted,
           case .success(let window) = focusedWindowManager.focusedWindow(accessibilityTrusted: true) {
            selection = PreviewWindowSelection(
                processIdentifier: window.identity.processIdentifier,
                title: window.title,
                frame: axFrame(of: window.element)
            )
        }
        previewManager.begin(selection: selection)
    }

    func selectPreviewWindow(_ window: PreviewWindow) {
        previewManager.select(window)
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
        guard requireAccessibility() else { return }

        switch focusedWindowManager.focusedWindow(accessibilityTrusted: true) {
        case .failure(let error):
            model.status = .unableToRaise(error.localizedDescription)
            notificationManager.show(message: "Unable to raise this window")
        case .success(let window):
            switch raiseManager.raiseOnce(window: window) {
            case .success:
                model.status = .windowRaisedOnce(window.summary)
                PinnyLogger.window.info("One-shot AXRaise fallback succeeded")
                notificationManager.show(message: "Raised once")
            case .failure(let error):
                model.status = .unableToRaise(error.localizedDescription)
                PinnyLogger.window.notice("One-shot AXRaise fallback failed: \(error.localizedDescription, privacy: .public)")
                notificationManager.show(message: "Unable to raise this window")
            }
        }
    }

    func hideCurrentWindow() {
        PinnyLogger.hotKey.debug("Hide-window action routed")
        guard requireAccessibility() else { return }

        switch focusedWindowManager.focusedWindow(accessibilityTrusted: true) {
        case .failure(let error):
            model.status = .unableToHide(error.localizedDescription)
            notificationManager.show(message: "Unable to hide this window")
        case .success(let window):
            switch visibilityManager.hide(window: window) {
            case .success(let summary):
                model.hiddenWindowCount = visibilityManager.hiddenWindowCount
                model.status = .windowHidden(summary)
                PinnyLogger.window.info("Window hide operation succeeded")
                notificationManager.show(message: "Hidden")
            case .failure(let error):
                model.hiddenWindowCount = visibilityManager.hiddenWindowCount
                model.status = .unableToHide(error.localizedDescription)
                PinnyLogger.window.notice("Window hide operation failed: \(error.localizedDescription, privacy: .public)")
                notificationManager.show(message: "Unable to hide this window")
            }
        }
    }

    func showLastHiddenWindow() {
        PinnyLogger.hotKey.debug("Show-window action routed")
        guard requireAccessibility() else { return }

        switch visibilityManager.showLastHidden() {
        case .success(let summary):
            model.hiddenWindowCount = visibilityManager.hiddenWindowCount
            model.status = .windowShown(summary)
            PinnyLogger.window.info("Window restore operation succeeded")
            notificationManager.show(message: "Restored")
        case .failure(let error):
            model.hiddenWindowCount = visibilityManager.hiddenWindowCount
            model.status = .unableToShow(error.localizedDescription)
            PinnyLogger.window.notice("Window restore operation failed: \(error.localizedDescription, privacy: .public)")
            notificationManager.show(message: error == .noHiddenWindows ? "No hidden window" : "Unable to restore window")
        }
    }

    func openAccessibilitySettings() {
        preferences.onboardingCompleted = true
        _ = accessibilityManager.openSystemSettings()
    }

    func refreshVisibleState() {
        refreshPermissionState()
        refreshLaunchAtLoginState()
        visibilityManager.removeStaleStateIfNeeded()
        model.hiddenWindowCount = visibilityManager.hiddenWindowCount
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

    func showAbout() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Pinny",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0",
            .credits: NSAttributedString(
                string: "A native menu bar utility for live, view-only window previews and window hide/restore shortcuts. Uses standard macOS permissions; no privileged helper required."
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
        previewManager.stop()
        notificationManager.cleanUp()
    }

    private func registerHotKeys() {
        let shortcuts: [(PinnyHotKey, HotKeyConfiguration, ShortcutAction)] = [
            (.togglePin, preferences.shortcutConfiguration, .togglePin),
            (.hideWindow, .controlPeriod, .hideWindow),
            (.showWindow, .controlComma, .showWindow)
        ]
        var failures: [String] = []

        for (identifier, configuration, action) in shortcuts {
            let result = hotKeyManager.register(
                identifier: identifier,
                configuration: configuration
            ) { [weak self] in
                self?.shortcutRouter.routeShortcut(action)
            }
            switch result {
            case .success:
                PinnyLogger.hotKey.info("Global \(configuration.displayName, privacy: .public) shortcut registered")
            case .failure(let error):
                PinnyLogger.hotKey.error("Global shortcut registration failed: \(error.localizedDescription, privacy: .public)")
                failures.append(error.localizedDescription)
            }
        }

        model.shortcutRegistrationFailure = failures.isEmpty
            ? nil
            : failures.joined(separator: "\n")
    }

    private func handlePreviewStateChange(_ state: WindowPreviewState) {
        let wasActive = model.previewState.activeWindow != nil
        model.previewState = state
        onPinnedStateChanged?(state.activeWindow != nil)

        switch state {
        case .active:
            if !wasActive {
                notificationManager.show(message: "Preview started")
            }
        case .idle:
            if wasActive {
                notificationManager.show(message: "Preview closed")
            }
        case .choosing, .failed:
            onPreviewNeedsAttention?()
        case .loading, .starting:
            break
        }
    }

    private func requireAccessibility() -> Bool {
        guard accessibilityManager.recheck() else {
            model.isAccessibilityTrusted = false
            model.status = .accessibilityPermissionRequired
            notificationManager.show(message: "Accessibility permission required")
            return false
        }
        model.isAccessibilityTrusted = true
        preferences.onboardingCompleted = true
        return true
    }

    private func axFrame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
            AXUIElementCopyAttributeValue(
                element,
                kAXSizeAttribute as CFString,
                &sizeValue
            ) == .success,
            let positionValue,
            let sizeValue,
            CFGetTypeID(positionValue) == AXValueGetTypeID(),
            CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        let positionAX = unsafeBitCast(positionValue, to: AXValue.self)
        let sizeAX = unsafeBitCast(sizeValue, to: AXValue.self)
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAX, .cgPoint, &point),
              AXValueGetValue(sizeAX, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: point, size: size)
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

    private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.focusedWindowManager.recordActivatedApplication(app)
            }
        })

        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                    return
                }
                self?.visibilityManager.removeState(forTerminatedProcess: app.processIdentifier)
                self?.model.hiddenWindowCount = self?.visibilityManager.hiddenWindowCount ?? 0
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshPermissionState()
                self?.refreshLaunchAtLoginState()
            }
        })
    }

    private func performHousekeeping() {
        visibilityManager.removeStaleStateIfNeeded()
        model.hiddenWindowCount = visibilityManager.hiddenWindowCount
        refreshPermissionState()
    }
}
