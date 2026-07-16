import Foundation

enum ShortcutAction {
    case togglePin
    case hideWindow
    case showWindow
}

final class ShortcutActionRouter {
    private let toggleAction: () -> Void
    private let hideAction: () -> Void
    private let showAction: () -> Void

    init(
        toggleAction: @escaping () -> Void,
        hideAction: @escaping () -> Void = {},
        showAction: @escaping () -> Void = {}
    ) {
        self.toggleAction = toggleAction
        self.hideAction = hideAction
        self.showAction = showAction
    }

    func routeShortcut(_ action: ShortcutAction = .togglePin) {
        switch action {
        case .togglePin:
            toggleAction()
        case .hideWindow:
            hideAction()
        case .showWindow:
            showAction()
        }
    }
}
