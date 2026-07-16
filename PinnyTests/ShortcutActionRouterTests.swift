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
    func testHideAndShowShortcutsRouteOnlyTheirOwnActions() {
        var events: [String] = []
        let router = ShortcutActionRouter(
            toggleAction: { events.append("pin") },
            hideAction: { events.append("hide") },
            showAction: { events.append("show") }
        )

        router.routeShortcut(.hideWindow)
        router.routeShortcut(.showWindow)
        router.routeShortcut(.togglePin)

        #expect(events == ["hide", "show", "pin"])
    }

    @Test
    func testDefaultShortcutUsesControlNotCommand() {
        #expect(HotKeyConfiguration.controlZ.carbonModifiers == UInt32(controlKey))
        #expect(HotKeyConfiguration.controlZ.carbonModifiers != UInt32(cmdKey))
        #expect(HotKeyConfiguration.controlZ.displayName == "⌃Z")
    }

    @Test
    func testWindowVisibilityShortcutsUseRequestedControlKeys() {
        #expect(HotKeyConfiguration.controlPeriod.keyCode == UInt32(kVK_ANSI_Period))
        #expect(HotKeyConfiguration.controlPeriod.carbonModifiers == UInt32(controlKey))
        #expect(HotKeyConfiguration.controlPeriod.displayName == "⌃.")
        #expect(HotKeyConfiguration.controlComma.keyCode == UInt32(kVK_ANSI_Comma))
        #expect(HotKeyConfiguration.controlComma.carbonModifiers == UInt32(controlKey))
        #expect(HotKeyConfiguration.controlComma.displayName == "⌃,")
    }
}
