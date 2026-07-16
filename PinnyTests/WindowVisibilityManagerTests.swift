import ApplicationServices
import Testing
@testable import Pinny

@Suite("Hidden window stack")
struct WindowVisibilityManagerTests {
    @Test
    func testHideThenShowRestoresMostRecentWindowFirst() {
        let controller = FakeWindowVisibilityController()
        let manager = WindowVisibilityManager(
            controller: controller,
            validityChecker: FakeVisibilityValidityChecker()
        )
        let first = makeVisibilityWindow(pid: 10, hash: 1, title: "First")
        let second = makeVisibilityWindow(pid: 11, hash: 2, title: "Second")

        _ = manager.hide(window: first)
        _ = manager.hide(window: second)
        let shown = manager.showLastHidden()

        #expect(summary(from: shown)?.windowTitle == "Second")
        #expect(manager.hiddenWindowCount == 1)
        #expect(controller.events == ["hide:1", "hide:2", "show:2"])
    }

    @Test
    func testFailedHideIsNeverRemembered() {
        let controller = FakeWindowVisibilityController()
        controller.hideResult = .failure(.minimizeUnsupported)
        let manager = WindowVisibilityManager(
            controller: controller,
            validityChecker: FakeVisibilityValidityChecker()
        )

        let result = manager.hide(window: makeVisibilityWindow(
            pid: 10,
            hash: 1,
            title: "Unsupported"
        ))

        #expect(error(from: result) == .minimizeUnsupported)
        #expect(manager.hiddenWindowCount == 0)
    }

    @Test
    func testTransientShowFailureKeepsWindowForRetry() {
        let controller = FakeWindowVisibilityController()
        let manager = WindowVisibilityManager(
            controller: controller,
            validityChecker: FakeVisibilityValidityChecker()
        )
        _ = manager.hide(window: makeVisibilityWindow(pid: 10, hash: 1, title: "Retry"))
        controller.showResult = .failure(.accessibilityFailure(
            operation: "restore",
            error: .cannotComplete
        ))

        _ = manager.showLastHidden()

        #expect(manager.hiddenWindowCount == 1)
    }

    @Test
    func testStaleTopEntryIsSkippedWhenRestoring() {
        let controller = FakeWindowVisibilityController()
        let validity = FakeVisibilityValidityChecker()
        let manager = WindowVisibilityManager(
            controller: controller,
            validityChecker: validity
        )
        let surviving = makeVisibilityWindow(pid: 10, hash: 1, title: "Surviving")
        let stale = makeVisibilityWindow(pid: 11, hash: 2, title: "Stale")
        _ = manager.hide(window: surviving)
        _ = manager.hide(window: stale)
        validity.invalidIdentities.insert(stale.identity)

        let shown = manager.showLastHidden()

        #expect(summary(from: shown)?.windowTitle == "Surviving")
        #expect(manager.hiddenWindowCount == 0)
        #expect(controller.events.last == "show:1")
    }

    @Test
    func testTerminatedApplicationEntriesAreRemoved() {
        let controller = FakeWindowVisibilityController()
        let manager = WindowVisibilityManager(
            controller: controller,
            validityChecker: FakeVisibilityValidityChecker()
        )
        _ = manager.hide(window: makeVisibilityWindow(pid: 10, hash: 1, title: "First"))
        _ = manager.hide(window: makeVisibilityWindow(pid: 11, hash: 2, title: "Second"))

        manager.removeState(forTerminatedProcess: 10)

        #expect(manager.hiddenWindowCount == 1)
        #expect(manager.hiddenWindows.first?.identity.processIdentifier == 11)
    }
}

private final class FakeWindowVisibilityController: WindowVisibilityControlling {
    var hideResult: Result<Void, WindowVisibilityError> = .success(())
    var showResult: Result<Void, WindowVisibilityError> = .success(())
    private(set) var events: [String] = []

    func hide(window: FocusedWindow) -> Result<Void, WindowVisibilityError> {
        events.append("hide:\(window.identity.accessibilityElementHash)")
        return hideResult
    }

    func show(window: FocusedWindow) -> Result<Void, WindowVisibilityError> {
        events.append("show:\(window.identity.accessibilityElementHash)")
        return showResult
    }
}

private final class FakeVisibilityValidityChecker: WindowValidityChecking {
    var invalidIdentities: Set<WindowIdentity> = []

    func isValid(window: FocusedWindow) -> Bool {
        !invalidIdentities.contains(window.identity)
    }
}

private func makeVisibilityWindow(
    pid: pid_t,
    hash: CFHashCode,
    title: String
) -> FocusedWindow {
    FocusedWindow(
        identity: WindowIdentity(processIdentifier: pid, accessibilityElementHash: hash),
        applicationName: "Safari",
        applicationBundleIdentifier: "com.apple.Safari",
        title: title,
        role: "AXWindow",
        subrole: "AXStandardWindow",
        element: AXUIElementCreateSystemWide()
    )
}

private func summary(
    from result: Result<PinnedWindowSummary, WindowVisibilityError>
) -> PinnedWindowSummary? {
    guard case .success(let summary) = result else { return nil }
    return summary
}

private func error(
    from result: Result<PinnedWindowSummary, WindowVisibilityError>
) -> WindowVisibilityError? {
    guard case .failure(let error) = result else { return nil }
    return error
}
