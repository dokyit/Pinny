import AppKit

@main
enum PinnyApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)

        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let preferences = PreferencesStore()
        let model = AppModel(shortcutDisplayName: preferences.shortcutConfiguration.displayName)
        let coordinator = AppCoordinator(model: model, preferences: preferences)
        let menuBarController = MenuBarController(model: model, actions: MenuBarActions(
            refreshState: { [weak coordinator] in coordinator?.refreshVisibleState() },
            toggleCurrentWindow: { [weak coordinator] in coordinator?.toggleCurrentWindow() },
            raiseCurrentWindowOnce: { [weak coordinator] in coordinator?.raiseCurrentWindowOnce() },
            requestAccessibility: { [weak coordinator] in coordinator?.requestAccessibilityPermission() },
            openAccessibilitySettings: { [weak coordinator] in coordinator?.openAccessibilitySettings() },
            setLaunchAtLogin: { [weak coordinator] enabled in coordinator?.setLaunchAtLogin(enabled) },
            openLoginItemsSettings: { [weak coordinator] in coordinator?.openLoginItemsSettings() },
            openAdvancedSetupGuide: { [weak coordinator] in coordinator?.openAdvancedSetupGuide() },
            showAbout: { [weak coordinator] in coordinator?.showAbout() },
            quit: { [weak coordinator] in coordinator?.quit() }
        ))

        coordinator.onPinnedStateChanged = { [weak menuBarController] isPinned in
            menuBarController?.setPinnedIcon(isPinned)
        }
        coordinator.onFirstLaunchNeedsPermission = { [weak menuBarController] in
            menuBarController?.showPopover()
        }

        self.coordinator = coordinator
        self.menuBarController = menuBarController
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.cleanUp()
        menuBarController?.cleanUp()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
