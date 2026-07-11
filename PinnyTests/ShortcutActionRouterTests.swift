import Carbon.HIToolbox
import Testing
@testable import Pinny

@Suite("Shortcut action routing")
struct ShortcutActionRouterTests {
    @Test
    func testShortcutRoutesToToggleExactlyOncePerInvocation() {
        var invocationCount = 0
        let router = ShortcutActionRouter {
            invocationCount += 1
        }

        router.routeShortcut()
        router.routeShortcut()

        #expect(invocationCount == 2)
    }

    @Test
    func testDefaultShortcutUsesControlNotCommand() {
        #expect(HotKeyConfiguration.controlZ.carbonModifiers == UInt32(controlKey))
        #expect(HotKeyConfiguration.controlZ.carbonModifiers != UInt32(cmdKey))
        #expect(HotKeyConfiguration.controlZ.displayName == "⌃Z")
    }
}
