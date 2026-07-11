import Foundation

final class ShortcutActionRouter {
    private let toggleAction: () -> Void

    init(toggleAction: @escaping () -> Void) {
        self.toggleAction = toggleAction
    }

    func routeShortcut() {
        toggleAction()
    }
}
