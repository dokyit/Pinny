import ApplicationServices
import Testing
@testable import Pinny

@Suite("Window pin state transitions")
struct WindowPinManagerTests {
    @Test
    func testSuccessfulPinThenUnpinTransitionsState() {
        let controller = FakeWindowLevelController()
        let manager = WindowPinManager(
            levelController: controller,
            validityChecker: AlwaysValidWindowChecker()
        )
        let window = makeWindow(pid: 41, hash: 101, app: "Safari", title: "One")

        #expect(
            manager.toggle(window: window)
                == .pinned(PinnedWindowSummary(applicationName: "Safari", windowTitle: "One"))
        )
        #expect(manager.pinnedWindow?.window.identity == window.identity)

        #expect(manager.toggle(window: window) == .unpinned)
        #expect(manager.pinnedWindow == nil)
        #expect(controller.pinCallCount == 1)
        #expect(controller.unpinCallCount == 1)
    }

    @Test
    func testFailedPinIsNeverStoredAsPinned() {
        let controller = FakeWindowLevelController()
        controller.pinResult = .failure(.unsupportedByPublicAPI)
        let manager = WindowPinManager(
            levelController: controller,
            validityChecker: AlwaysValidWindowChecker()
        )

        let result = manager.toggle(window: makeWindow(pid: 50, hash: 202))

        #expect(result == .unable(.unsupportedByPublicAPI))
        #expect(manager.pinnedWindow == nil)
    }

    @Test
    func testFailedUnpinRetainsPinnedState() {
        let controller = FakeWindowLevelController()
        let manager = WindowPinManager(
            levelController: controller,
            validityChecker: AlwaysValidWindowChecker()
        )
        let window = makeWindow(pid: 55, hash: 303)
        _ = manager.toggle(window: window)
        controller.unpinResult = .failure(.restorationFailed("restore failed"))

        let result = manager.toggle(window: window)

        #expect(result == .unable(.restorationFailed("restore failed")))
        #expect(manager.pinnedWindow?.window.identity == window.identity)
    }

    @Test
    func testSwitchingWindowsUnpinsFirstWindowBeforePinningSecond() {
        let controller = FakeWindowLevelController()
        let manager = WindowPinManager(
            levelController: controller,
            validityChecker: AlwaysValidWindowChecker()
        )
        let first = makeWindow(pid: 60, hash: 1, app: "Safari", title: "First")
        let second = makeWindow(pid: 60, hash: 2, app: "Safari", title: "Second")

        _ = manager.toggle(window: first)
        let result = manager.toggle(window: second)

        #expect(
            result
                == .pinned(PinnedWindowSummary(applicationName: "Safari", windowTitle: "Second"))
        )
        #expect(manager.pinnedWindow?.window.identity == second.identity)
        #expect(controller.events == ["pin:1", "unpin:1", "pin:2"])
    }

    @Test
    func testTerminatedOwningProcessClearsState() {
        let manager = WindowPinManager(
            levelController: FakeWindowLevelController(),
            validityChecker: AlwaysValidWindowChecker()
        )
        _ = manager.toggle(window: makeWindow(pid: 73, hash: 7))

        manager.removeState(forTerminatedProcess: 73)

        #expect(manager.pinnedWindow == nil)
    }

    @Test
    func testStaleWindowClearsState() {
        let validity = MutableWindowChecker(isValid: true)
        let manager = WindowPinManager(
            levelController: FakeWindowLevelController(),
            validityChecker: validity
        )
        _ = manager.toggle(window: makeWindow(pid: 80, hash: 8))
        validity.isValid = false

        manager.removeStaleStateIfNeeded()

        #expect(manager.pinnedWindow == nil)
    }

    @Test
    func testRapidRepeatedToggleRemainsConsistent() {
        let controller = FakeWindowLevelController()
        let manager = WindowPinManager(
            levelController: controller,
            validityChecker: AlwaysValidWindowChecker()
        )
        let window = makeWindow(pid: 90, hash: 9)

        for _ in 0..<100 {
            _ = manager.toggle(window: window)
        }

        #expect(manager.pinnedWindow == nil)
        #expect(controller.pinCallCount == 50)
        #expect(controller.unpinCallCount == 50)
    }
}

private final class FakeWindowLevelController: WindowLevelControlling {
    var pinResult: Result<WindowLevelToken, WindowPinningError> = .success(WindowLevelToken(rawValue: "token"))
    var unpinResult: Result<Void, WindowPinningError> = .success(())
    var pinCallCount = 0
    var unpinCallCount = 0
    var events: [String] = []

    func pin(window: FocusedWindow) -> Result<WindowLevelToken, WindowPinningError> {
        pinCallCount += 1
        events.append("pin:\(window.identity.accessibilityElementHash)")
        return pinResult
    }

    func unpin(window: FocusedWindow, token: WindowLevelToken) -> Result<Void, WindowPinningError> {
        unpinCallCount += 1
        events.append("unpin:\(window.identity.accessibilityElementHash)")
        return unpinResult
    }
}

private struct AlwaysValidWindowChecker: WindowValidityChecking {
    func isValid(window: FocusedWindow) -> Bool { true }
}

private final class MutableWindowChecker: WindowValidityChecking {
    var isValid: Bool

    init(isValid: Bool) {
        self.isValid = isValid
    }

    func isValid(window: FocusedWindow) -> Bool { isValid }
}

private func makeWindow(
    pid: pid_t,
    hash: CFHashCode,
    app: String = "TextEdit",
    title: String? = "Document"
) -> FocusedWindow {
    FocusedWindow(
        identity: WindowIdentity(processIdentifier: pid, accessibilityElementHash: hash),
        applicationName: app,
        applicationBundleIdentifier: "com.example.\(app.lowercased())",
        title: title,
        role: "AXWindow",
        subrole: "AXStandardWindow",
        element: AXUIElementCreateSystemWide()
    )
}
