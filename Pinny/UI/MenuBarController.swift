import AppKit
import SwiftUI

struct MenuBarActions {
    let refreshState: () -> Void
    let toggleCurrentWindow: () -> Void
    let hideCurrentWindow: () -> Void
    let showLastHiddenWindow: () -> Void
    let raiseCurrentWindowOnce: () -> Void
    let requestAccessibility: () -> Void
    let openAccessibilitySettings: () -> Void
    let setLaunchAtLogin: (Bool) -> Void
    let openLoginItemsSettings: () -> Void
    let openAdvancedSetupGuide: () -> Void
    let showAbout: () -> Void
    let quit: () -> Void
}

final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let idleImage: NSImage
    private let pinnedImage: NSImage
    private let actions: MenuBarActions
    private var removedFromStatusBar = false

    init(model: AppModel, actions: MenuBarActions) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        idleImage = ResourceLocator.menuBarImage(
            assetName: "MenuBarIdle",
            fallbackFileName: "MenuBarIdle",
            symbolName: "pin"
        )
        pinnedImage = ResourceLocator.menuBarImage(
            assetName: "MenuBarPinned",
            fallbackFileName: "MenuBarPinned",
            symbolName: "pin.fill"
        )
        self.actions = actions
        super.init()

        statusItem.button?.image = idleImage
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "Pinny"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let hostingController = NSHostingController(
            rootView: MenuBarView(model: model, actions: actions)
        )
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
    }

    func setPinnedIcon(_ pinned: Bool) {
        statusItem.button?.image = pinned ? pinnedImage : idleImage
        statusItem.button?.toolTip = pinned ? "Pinny — Window pinned" : "Pinny"
    }

    func cleanUp() {
        popover.performClose(nil)
        guard !removedFromStatusBar else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        removedFromStatusBar = true
    }

    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        actions.refreshState()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    deinit {
        cleanUp()
    }
}
