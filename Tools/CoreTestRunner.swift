import ApplicationServices
import Carbon.HIToolbox
import Foundation

@main
struct CoreTestRunner {
    static func main() {
        var suite = CoreTestSuite()
        suite.runAll()
        suite.finish()
    }
}

private struct CoreTestSuite {
    private var passed = 0
    private var failed = 0

    mutating func runAll() {
        test("equal window identity") {
            WindowIdentity(processIdentifier: 1, accessibilityElementHash: 10)
                == WindowIdentity(processIdentifier: 1, accessibilityElementHash: 10)
        }
        test("two windows in one process remain distinct") {
            WindowIdentity(processIdentifier: 1, accessibilityElementHash: 10)
                != WindowIdentity(processIdentifier: 1, accessibilityElementHash: 11)
        }
        test("same AX hash in two processes remains distinct") {
            WindowIdentity(processIdentifier: 1, accessibilityElementHash: 10)
                != WindowIdentity(processIdentifier: 2, accessibilityElementHash: 10)
        }

        runPreferenceTests()

        test("Dock is rejected") {
            UnsupportedWindowFilter.rejectionReason(
                bundleIdentifier: "com.apple.dock",
                applicationName: "Dock",
                role: "AXWindow"
            ) != nil
        }
        test("menu bar role is rejected") {
            UnsupportedWindowFilter.rejectionReason(
                bundleIdentifier: "com.apple.TextEdit",
                applicationName: "TextEdit",
                role: "AXMenuBar"
            ) != nil
        }
        test("Finder application window is accepted") {
            UnsupportedWindowFilter.rejectionReason(
                bundleIdentifier: "com.apple.finder",
                applicationName: "Finder",
                role: "AXWindow"
            ) == nil
        }
        test("application sheet is accepted") {
            UnsupportedWindowFilter.rejectionReason(
                bundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                role: "AXSheet"
            ) == nil
        }

        let ready = MenuPresentation.make(status: .ready, isAccessibilityTrusted: true)
        test("ready menu status") {
            ready.statusTitle == "Ready" && ready.canToggleWindow
                && ready.actionTitle == "Pin Current Window"
        }
        let pinned = MenuPresentation.make(
            status: .windowPinned(PinnedWindowSummary(
                applicationName: "Safari",
                windowTitle: "YouTube"
            )),
            isAccessibilityTrusted: true
        )
        test("pinned menu identifies individual window") {
            pinned.statusDetail == "Pinned: Safari — YouTube"
                && pinned.actionTitle == "Unpin Current Window"
        }
        let missingPermission = MenuPresentation.make(
            status: .shortcutRegistrationFailed("busy"),
            isAccessibilityTrusted: false
        )
        test("permission status takes priority") {
            missingPermission.statusTitle == "Accessibility permission required"
                && !missingPermission.canToggleWindow
        }
        let unable = MenuPresentation.make(
            status: .unableToPin("Public API unavailable"),
            isAccessibilityTrusted: true
        )
        test("failed pin reason is shown honestly") {
            unable.statusTitle == "Unable to pin this window"
                && unable.statusDetail == "Public API unavailable"
        }
        let raisedOnce = MenuPresentation.make(
            status: .windowRaisedOnce(PinnedWindowSummary(
                applicationName: "Calculator",
                windowTitle: nil
            )),
            isAccessibilityTrusted: true
        )
        test("one-shot raise fallback never claims pin success") {
            let raiseFailure = MenuPresentation.make(
                status: .unableToRaise("AXRaise unsupported"),
                isAccessibilityTrusted: true
            )
            return raisedOnce.statusTitle == "Raised once (fallback)"
                && raisedOnce.statusDetail?.contains("It is not pinned") == true
                && raisedOnce.actionTitle == "Pin Current Window"
                && raiseFailure.statusTitle == "Unable to raise this window"
        }

        var routedCount = 0
        let router = ShortcutActionRouter { routedCount += 1 }
        router.routeShortcut()
        router.routeShortcut()
        test("shortcut routes once per event") { routedCount == 2 }
        test("default shortcut is Control+Z, not Command+Z") {
            let failurePresentation = MenuPresentation.make(
                status: .windowPinned(PinnedWindowSummary(
                    applicationName: "Safari",
                    windowTitle: "Document"
                )),
                isAccessibilityTrusted: true,
                shortcutRegistrationFailure: "shortcut busy"
            )
            return HotKeyConfiguration.controlZ.carbonModifiers == UInt32(controlKey)
                && HotKeyConfiguration.controlZ.carbonModifiers != UInt32(cmdKey)
                && HotKeyConfiguration.controlZ.displayName == "⌃Z"
                && failurePresentation.statusTitle == "Shortcut registration failed"
                && failurePresentation.actionTitle == "Unpin Current Window"
        }
        test("hide and show shortcuts use the requested Control keys") {
            HotKeyConfiguration.controlPeriod.keyCode == UInt32(kVK_ANSI_Period)
                && HotKeyConfiguration.controlPeriod.carbonModifiers == UInt32(controlKey)
                && HotKeyConfiguration.controlPeriod.displayName == "⌃."
                && HotKeyConfiguration.controlComma.keyCode == UInt32(kVK_ANSI_Comma)
                && HotKeyConfiguration.controlComma.carbonModifiers == UInt32(controlKey)
                && HotKeyConfiguration.controlComma.displayName == "⌃,"
        }
        var shortcutEvents: [String] = []
        let multiActionRouter = ShortcutActionRouter(
            toggleAction: { shortcutEvents.append("pin") },
            hideAction: { shortcutEvents.append("hide") },
            showAction: { shortcutEvents.append("show") }
        )
        multiActionRouter.routeShortcut(.hideWindow)
        multiActionRouter.routeShortcut(.showWindow)
        multiActionRouter.routeShortcut(.togglePin)
        test("each global shortcut routes only its own action") {
            shortcutEvents == ["hide", "show", "pin"]
        }

        runVisibilityTests()
        runPinStateTests()
        runYabaiControllerTests()
        runYabaiServiceTests()
    }

    private mutating func runVisibilityTests() {
        let controller = CoreFakeWindowVisibilityController()
        let validity = CoreVisibilityValidityChecker()
        let manager = WindowVisibilityManager(
            controller: controller,
            validityChecker: validity
        )
        let first = makeWindow(pid: 44, hash: 101, title: "First hidden")
        let second = makeWindow(pid: 45, hash: 102, title: "Second hidden")

        _ = manager.hide(window: first)
        _ = manager.hide(window: second)
        let secondRestore = manager.showLastHidden()
        test("hidden windows restore in last-in-first-out order") {
            coreVisibilitySummary(secondRestore)?.windowTitle == "Second hidden"
                && manager.hiddenWindowCount == 1
                && controller.events == ["hide:101", "hide:102", "show:102"]
        }

        controller.showResult = .failure(.accessibilityFailure(
            operation: "restore",
            error: .cannotComplete
        ))
        _ = manager.showLastHidden()
        test("transient restore failure retains hidden window for retry") {
            manager.hiddenWindowCount == 1
        }

        controller.showResult = .success(())
        validity.invalidIdentities.insert(first.identity)
        test("stale hidden window is discarded safely") {
            coreVisibilityError(manager.showLastHidden()) == .noHiddenWindows
                && manager.hiddenWindowCount == 0
        }

        controller.hideResult = .failure(.minimizeUnsupported)
        let failedHide = manager.hide(window: first)
        test("failed hide is never added to restore stack") {
            coreVisibilityError(failedHide) == .minimizeUnsupported
                && manager.hiddenWindowCount == 0
        }

        controller.hideResult = .success(())
        validity.invalidIdentities.removeAll()
        _ = manager.hide(window: first)
        _ = manager.hide(window: second)
        manager.removeState(forTerminatedProcess: 44)
        test("terminated application is removed from hidden stack") {
            manager.hiddenWindowCount == 1
                && manager.hiddenWindows.first?.identity.processIdentifier == 45
        }
    }

    private mutating func runPreferenceTests() {
        let suiteName = "PinnyCoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fail("create isolated preferences suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        let first = PreferencesStore(defaults: defaults)
        first.onboardingCompleted = true
        test("onboarding completion persists") {
            PreferencesStore(defaults: defaults).onboardingCompleted
        }

        let custom = HotKeyConfiguration(keyCode: 12, carbonModifiers: 4096, displayName: "⌃Q")
        first.shortcutConfiguration = custom
        test("shortcut configuration persists") {
            PreferencesStore(defaults: defaults).shortcutConfiguration == custom
        }

        defaults.set(Data([0xFF, 0x00]), forKey: "shortcutConfiguration")
        test("corrupt shortcut falls back safely") {
            PreferencesStore(defaults: defaults).shortcutConfiguration == .controlZ
        }
    }

    private mutating func runPinStateTests() {
        let controller = CoreFakeWindowLevelController()
        let validity = CoreMutableValidityChecker(isValid: true)
        let manager = WindowPinManager(levelController: controller, validityChecker: validity)
        let first = makeWindow(pid: 44, hash: 1, title: "First")
        let second = makeWindow(pid: 44, hash: 2, title: "Second")

        test("first toggle pins one individual window") {
            manager.toggle(window: first)
                == .pinned(PinnedWindowSummary(applicationName: "Safari", windowTitle: "First"))
                && manager.pinnedWindow?.window.identity == first.identity
        }
        test("different window unpins then pins in order") {
            manager.toggle(window: second)
                == .pinned(PinnedWindowSummary(applicationName: "Safari", windowTitle: "Second"))
                && controller.events == ["pin:1", "unpin:1", "pin:2"]
        }
        test("same window toggles back to unpinned") {
            manager.toggle(window: second) == .unpinned && manager.pinnedWindow == nil
        }

        controller.pinResult = .failure(.unsupportedByPublicAPI)
        test("unsupported public API never creates pinned state") {
            manager.toggle(window: first) == .unable(.unsupportedByPublicAPI)
                && manager.pinnedWindow == nil
        }

        let failedUnpinController = CoreFakeWindowLevelController()
        let failedUnpinManager = WindowPinManager(
            levelController: failedUnpinController,
            validityChecker: CoreMutableValidityChecker(isValid: true)
        )
        _ = failedUnpinManager.toggle(window: first)
        failedUnpinController.unpinResult = .failure(.restorationFailed("restore failed"))
        test("failed unpin retains truthful pinned state") {
            failedUnpinManager.toggle(window: first)
                == .unable(.restorationFailed("restore failed"))
                && failedUnpinManager.pinnedWindow?.window.identity == first.identity
        }

        controller.pinResult = .success(WindowLevelToken(rawValue: "token"))
        _ = manager.toggle(window: first)
        validity.isValid = false
        manager.removeStaleStateIfNeeded()
        test("stale accessibility reference is removed") { manager.pinnedWindow == nil }

        validity.isValid = true
        _ = manager.toggle(window: first)
        manager.removeState(forTerminatedProcess: 44)
        test("terminated owning application clears state") { manager.pinnedWindow == nil }

        let rapidController = CoreFakeWindowLevelController()
        let rapidManager = WindowPinManager(
            levelController: rapidController,
            validityChecker: CoreMutableValidityChecker(isValid: true)
        )
        for _ in 0..<100 {
            _ = rapidManager.toggle(window: first)
        }
        test("rapid repeated toggles end in a consistent state") {
            rapidManager.pinnedWindow == nil
                && rapidController.pinCallCount == 50
                && rapidController.unpinCallCount == 50
        }
    }

    private mutating func runYabaiControllerTests() {
        let verifiedService = CoreFakeYabaiWindowService(
            windowID: 301,
            ownerProcessIdentifier: 701,
            subLayer: "normal"
        )
        let verifiedController = YabaiWindowLevelController(service: verifiedService)
        let verifiedWindow = makeWindow(pid: 701, hash: 301, title: "Verified")
        let verifiedPin = verifiedController.pin(window: verifiedWindow)
        let verifiedToken: WindowLevelToken?
        if case .success(let token) = verifiedPin {
            verifiedToken = token
        } else {
            verifiedToken = nil
        }
        test("yabai pin requires verified above readback") {
            verifiedToken?.yabaiState == YabaiWindowRestorationState(
                ownerProcessIdentifier: 701,
                windowID: 301,
                originalSubLayer: "normal"
            )
                && verifiedService.records[301]?.subLayer == "above"
                && verifiedService.setCalls == [
                    CoreSetSubLayerCall(windowID: 301, subLayer: "above")
                ]
        }

        let verifiedRestore = verifiedToken.map {
            verifiedController.unpin(window: verifiedWindow, token: $0)
        }
        test("yabai unpin restores the exact original sub-layer") {
            verifiedRestore.map(coreVoidResultSucceeded) == true
                && verifiedService.records[301]?.subLayer == "normal"
                && verifiedService.setCalls == [
                    CoreSetSubLayerCall(windowID: 301, subLayer: "above"),
                    CoreSetSubLayerCall(windowID: 301, subLayer: "normal")
                ]
        }

        let mismatchService = CoreFakeYabaiWindowService(
            windowID: 302,
            ownerProcessIdentifier: 999,
            subLayer: "normal"
        )
        let mismatchResult = YabaiWindowLevelController(service: mismatchService).pin(
            window: makeWindow(pid: 702, hash: 302, title: "Mismatch")
        )
        test("owner mismatch is rejected before mutation") {
            mismatchResult == .failure(.ownerMismatch(expected: 702, actual: 999))
                && mismatchService.setCalls.isEmpty
        }

        let recycledService = CoreFakeYabaiWindowService(
            windowID: 303,
            ownerProcessIdentifier: 703,
            subLayer: "below"
        )
        let recycledController = YabaiWindowLevelController(service: recycledService)
        let recycledWindow = makeWindow(pid: 703, hash: 303, title: "Recycled")
        let recycledPin = recycledController.pin(window: recycledWindow)
        var recycledRestoreError: WindowPinningError?
        var recycledMaintenance: WindowLevelMaintenanceResult?
        if case .success(let token) = recycledPin {
            recycledService.records[303] = YabaiWindowRecord(
                windowID: 303,
                ownerProcessIdentifier: 888,
                subLayer: "normal"
            )
            recycledRestoreError = coreVoidResultFailure(
                recycledController.unpin(window: recycledWindow, token: token)
            )
            recycledMaintenance = recycledController.maintain(
                window: recycledWindow,
                token: token
            )
        }
        test("recycled window ID is never restored into a new owner's window") {
            recycledRestoreError == .ownerMismatch(expected: 703, actual: 888)
                && recycledMaintenance == .targetGone
                && recycledService.setCalls == [
                    CoreSetSubLayerCall(windowID: 303, subLayer: "above")
                ]
        }

        let setFailureService = CoreFakeYabaiWindowService(
            windowID: 304,
            ownerProcessIdentifier: 704,
            subLayer: "normal"
        )
        setFailureService.setResults = [
            .failure(.advancedHelperUnavailable("mutation denied"))
        ]
        let setFailureResult = YabaiWindowLevelController(service: setFailureService).pin(
            window: makeWindow(pid: 704, hash: 304, title: "Set Failure")
        )
        test("yabai set failure never creates a restoration token") {
            setFailureResult == .failure(.advancedHelperUnavailable("mutation denied"))
                && setFailureService.records[304]?.subLayer == "normal"
        }

        let verificationFailureService = CoreFakeYabaiWindowService(
            windowID: 305,
            ownerProcessIdentifier: 705,
            subLayer: "normal"
        )
        verificationFailureService.mutateRecordAfterSuccessfulSet = false
        let verificationFailure = YabaiWindowLevelController(
            service: verificationFailureService
        ).pin(window: makeWindow(pid: 705, hash: 305, title: "Verify Failure"))
        test("successful helper exit without above readback is a failed pin") {
            verificationFailure == .failure(.verificationFailed(
                expected: "above",
                actual: "normal"
            ))
        }

        let sameIDService = CoreFakeYabaiWindowService(
            windowID: 306,
            ownerProcessIdentifier: 706,
            subLayer: "normal"
        )
        let sameIDController = YabaiWindowLevelController(service: sameIDService)
        let originalReference = makeWindow(pid: 706, hash: 306, title: "Original AX")
        let newReference = makeWindow(pid: 706, hash: 307, title: "New AX")
        let sameIDPin = sameIDController.pin(window: originalReference)
        var sameIDMatched = false
        if case .success(let token) = sameIDPin {
            sameIDMatched = sameIDController.representsSameWindow(
                candidate: newReference,
                pinnedWindow: originalReference,
                token: token
            )
        }
        test("same WindowServer ID matches across differing AX identities") {
            originalReference.identity != newReference.identity && sameIDMatched
        }

        let driftService = CoreFakeYabaiWindowService(
            windowID: 307,
            ownerProcessIdentifier: 707,
            subLayer: "normal"
        )
        let driftController = YabaiWindowLevelController(service: driftService)
        let driftWindow = makeWindow(pid: 707, hash: 308, title: "Drift")
        let driftPin = driftController.pin(window: driftWindow)
        var driftMaintenance: WindowLevelMaintenanceResult?
        if case .success(let token) = driftPin {
            driftService.records[307] = YabaiWindowRecord(
                windowID: 307,
                ownerProcessIdentifier: 707,
                subLayer: "normal"
            )
            driftMaintenance = driftController.maintain(window: driftWindow, token: token)
        }
        test("maintenance reapplies above after compositor drift") {
            driftMaintenance == .reapplied
                && driftService.records[307]?.subLayer == "above"
                && driftService.setCalls == [
                    CoreSetSubLayerCall(windowID: 307, subLayer: "above"),
                    CoreSetSubLayerCall(windowID: 307, subLayer: "above")
                ]
        }

        let goneService = CoreFakeYabaiWindowService(
            windowID: 308,
            ownerProcessIdentifier: 708,
            subLayer: "normal"
        )
        let goneManager = WindowPinManager(
            levelController: YabaiWindowLevelController(service: goneService)
        )
        _ = goneManager.toggle(
            window: makeWindow(pid: 708, hash: 309, title: "Gone")
        )
        goneService.records.removeValue(forKey: 308)
        let goneMaintenance = goneManager.removeStaleStateIfNeeded()
        test("stale yabai target clears manager state without another mutation") {
            goneMaintenance == .targetGone
                && goneManager.pinnedWindow == nil
                && goneService.setCalls == [
                    CoreSetSubLayerCall(windowID: 308, subLayer: "above")
                ]
        }

        let retainedService = CoreFakeYabaiWindowService(
            windowID: 309,
            ownerProcessIdentifier: 709,
            subLayer: "normal"
        )
        let retainedManager = WindowPinManager(
            levelController: YabaiWindowLevelController(service: retainedService)
        )
        let retainedWindow = makeWindow(pid: 709, hash: 310, title: "Retained")
        _ = retainedManager.toggle(window: retainedWindow)
        retainedService.setResults = [
            .failure(.advancedHelperUnavailable("restore blocked")),
            .failure(.advancedHelperUnavailable("restore blocked"))
        ]
        let retainedResult = retainedManager.toggle(window: retainedWindow)
        test("failed verified unpin retries and retains truthful manager state") {
            retainedResult == .unable(.restorationFailed("restore blocked"))
                && retainedManager.pinnedWindow?.restorationToken.yabaiState?.windowID == 309
                && retainedService.setCalls.suffix(2) == [
                    CoreSetSubLayerCall(windowID: 309, subLayer: "normal"),
                    CoreSetSubLayerCall(windowID: 309, subLayer: "normal")
                ]
        }

        let switchService = CoreFakeYabaiWindowService(
            windowID: 310,
            ownerProcessIdentifier: 710,
            subLayer: "normal"
        )
        switchService.records[311] = YabaiWindowRecord(
            windowID: 311,
            ownerProcessIdentifier: 710,
            subLayer: "below"
        )
        switchService.windowIDResults = [.success(310), .success(311), .success(311)]
        let switchManager = WindowPinManager(
            levelController: YabaiWindowLevelController(service: switchService)
        )
        _ = switchManager.toggle(
            window: makeWindow(pid: 710, hash: 311, title: "First Generic")
        )
        let switched = switchManager.toggle(
            window: makeWindow(pid: 710, hash: 312, title: "Second Generic")
        )
        test("different-window policy restores old target before pinning new target") {
            switched == .pinned(PinnedWindowSummary(
                applicationName: "Safari",
                windowTitle: "Second Generic"
            ))
                && switchManager.pinnedWindow?.restorationToken.yabaiState?.windowID == 311
                && switchService.records[310]?.subLayer == "normal"
                && switchService.records[311]?.subLayer == "above"
                && switchService.setCalls == [
                    CoreSetSubLayerCall(windowID: 310, subLayer: "above"),
                    CoreSetSubLayerCall(windowID: 310, subLayer: "normal"),
                    CoreSetSubLayerCall(windowID: 311, subLayer: "above")
                ]
        }

        let blockedSwitchService = CoreFakeYabaiWindowService(
            windowID: 312,
            ownerProcessIdentifier: 712,
            subLayer: "normal"
        )
        blockedSwitchService.records[313] = YabaiWindowRecord(
            windowID: 313,
            ownerProcessIdentifier: 712,
            subLayer: "normal"
        )
        blockedSwitchService.windowIDResults = [.success(312), .success(313)]
        let blockedSwitchManager = WindowPinManager(
            levelController: YabaiWindowLevelController(service: blockedSwitchService)
        )
        _ = blockedSwitchManager.toggle(
            window: makeWindow(pid: 712, hash: 313, title: "Blocked First")
        )
        blockedSwitchService.setResults = [
            .failure(.advancedHelperUnavailable("restore blocked")),
            .failure(.advancedHelperUnavailable("restore blocked"))
        ]
        let blockedSwitch = blockedSwitchManager.toggle(
            window: makeWindow(pid: 712, hash: 314, title: "Blocked Second")
        )
        test("different-window policy never pins second target after failed restore") {
            blockedSwitch == .unable(.restorationFailed("restore blocked"))
                && blockedSwitchManager.pinnedWindow?.restorationToken.yabaiState?.windowID == 312
                && blockedSwitchService.records[312]?.subLayer == "above"
                && blockedSwitchService.records[313]?.subLayer == "normal"
                && !blockedSwitchService.setCalls.contains(
                    CoreSetSubLayerCall(windowID: 313, subLayer: "above")
                )
        }
    }

    private mutating func runYabaiServiceTests() {
        let queryRunner = CoreFakeYabaiCommandRunner(results: [
            .success(coreCommandResult(
                output: #"{"id":401,"pid":801,"sub-layer":"above"}"#
            ))
        ])
        let queryService = coreYabaiService(runner: queryRunner)
        let queryResult = queryService.windowRecord(for: 401)
        test("yabai service parses and scopes a window query") {
            queryResult == .success(YabaiWindowRecord(
                windowID: 401,
                ownerProcessIdentifier: 801,
                subLayer: "above"
            ))
                && queryRunner.invocations == [CoreYabaiInvocation(
                    executablePath: "/tmp/pinny-core-tests-yabai",
                    arguments: ["-m", "query", "--windows", "--window", "401"]
                )]
        }

        let staleRunner = CoreFakeYabaiCommandRunner(results: [
            .success(coreCommandResult(
                output: #"{"id":999,"pid":802,"sub-layer":"normal"}"#
            ))
        ])
        test("yabai service rejects a mismatched queried window ID") {
            coreYabaiService(runner: staleRunner).windowRecord(for: 402)
                == .failure(.staleWindow)
        }

        let setRunner = CoreFakeYabaiCommandRunner(results: [
            .success(coreCommandResult())
        ])
        let setResult = coreYabaiService(runner: setRunner).setSubLayer("below", for: 403)
        test("yabai service sends only narrow sub-layer mutation arguments") {
            coreVoidResultSucceeded(setResult)
                && setRunner.invocations == [CoreYabaiInvocation(
                    executablePath: "/tmp/pinny-core-tests-yabai",
                    arguments: ["-m", "window", "403", "--sub-layer", "below"]
                )]
        }

        let rejectedRunner = CoreFakeYabaiCommandRunner(results: [])
        let rejectedResult = coreYabaiService(runner: rejectedRunner).setSubLayer(
            "ceiling",
            for: 404
        )
        test("yabai service rejects unknown sub-layer without launching helper") {
            coreVoidResultFailure(rejectedResult) == .targetRejected(
                "Pinny refused an unknown window sub-layer."
            ) && rejectedRunner.invocations.isEmpty
        }

        let failedRunner = CoreFakeYabaiCommandRunner(results: [
            .success(coreCommandResult(
                status: 1,
                error: "scripting addition not loaded\n"
            ))
        ])
        test("yabai helper stderr is surfaced as an actionable failure") {
            coreYabaiService(runner: failedRunner).windowRecord(for: 405)
                == .failure(.advancedHelperUnavailable("scripting addition not loaded"))
        }

        let malformedRunner = CoreFakeYabaiCommandRunner(results: [
            .success(coreCommandResult(output: "not json"))
        ])
        test("malformed yabai JSON can never verify a target") {
            coreYabaiService(runner: malformedRunner).windowRecord(for: 406)
                == .failure(.advancedHelperUnavailable(
                    "yabai returned invalid JSON while Pinny verified the target window."
                ))
        }
    }

    private mutating func test(_ name: String, _ condition: () -> Bool) {
        if condition() {
            passed += 1
            print("PASS  \(name)")
        } else {
            fail(name)
        }
    }

    private mutating func fail(_ name: String) {
        failed += 1
        print("FAIL  \(name)")
    }

    func finish() -> Never {
        print("\nCore tests: \(passed) passed, \(failed) failed")
        exit(failed == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}

private final class CoreFakeWindowLevelController: WindowLevelControlling {
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

private struct CoreSetSubLayerCall: Equatable {
    let windowID: CGWindowID
    let subLayer: String
}

private final class CoreFakeYabaiWindowService: YabaiWindowServicing {
    var defaultWindowID: CGWindowID
    var windowIDResults: [Result<CGWindowID, WindowPinningError>] = []
    var records: [CGWindowID: YabaiWindowRecord]
    var recordResults: [Result<YabaiWindowRecord, WindowPinningError>] = []
    var setResults: [Result<Void, WindowPinningError>] = []
    var mutateRecordAfterSuccessfulSet = true
    private(set) var setCalls: [CoreSetSubLayerCall] = []

    init(
        windowID: CGWindowID,
        ownerProcessIdentifier: pid_t,
        subLayer: String
    ) {
        defaultWindowID = windowID
        records = [
            windowID: YabaiWindowRecord(
                windowID: windowID,
                ownerProcessIdentifier: ownerProcessIdentifier,
                subLayer: subLayer
            )
        ]
    }

    func windowID(for element: AXUIElement) -> Result<CGWindowID, WindowPinningError> {
        if !windowIDResults.isEmpty {
            return windowIDResults.removeFirst()
        }
        return .success(defaultWindowID)
    }

    func windowRecord(
        for windowID: CGWindowID
    ) -> Result<YabaiWindowRecord, WindowPinningError> {
        if !recordResults.isEmpty {
            return recordResults.removeFirst()
        }
        guard let record = records[windowID] else {
            return .failure(.staleWindow)
        }
        return .success(record)
    }

    func setSubLayer(
        _ subLayer: String,
        for windowID: CGWindowID
    ) -> Result<Void, WindowPinningError> {
        setCalls.append(CoreSetSubLayerCall(windowID: windowID, subLayer: subLayer))
        let result = setResults.isEmpty ? .success(()) : setResults.removeFirst()
        guard case .success = result,
              mutateRecordAfterSuccessfulSet,
              let current = records[windowID] else {
            return result
        }
        records[windowID] = YabaiWindowRecord(
            windowID: current.windowID,
            ownerProcessIdentifier: current.ownerProcessIdentifier,
            subLayer: subLayer
        )
        return result
    }
}

private struct CoreYabaiInvocation: Equatable {
    let executablePath: String
    let arguments: [String]
}

private final class CoreFakeYabaiCommandRunner: YabaiCommandRunning {
    var results: [Result<YabaiCommandResult, Error>]
    private(set) var invocations: [CoreYabaiInvocation] = []

    init(results: [Result<YabaiCommandResult, Error>]) {
        self.results = results
    }

    func run(
        executableURL: URL,
        arguments: [String]
    ) -> Result<YabaiCommandResult, Error> {
        invocations.append(CoreYabaiInvocation(
            executablePath: executableURL.path,
            arguments: arguments
        ))
        guard !results.isEmpty else {
            return .failure(CoreYabaiRunnerError.noQueuedResult)
        }
        return results.removeFirst()
    }
}

private enum CoreYabaiRunnerError: Error {
    case noQueuedResult
}

private func coreYabaiService(
    runner: CoreFakeYabaiCommandRunner
) -> YabaiWindowService {
    YabaiWindowService(
        executableURL: URL(fileURLWithPath: "/tmp/pinny-core-tests-yabai"),
        runner: runner
    )
}

private func coreCommandResult(
    status: Int32 = 0,
    output: String = "",
    error: String = ""
) -> YabaiCommandResult {
    YabaiCommandResult(
        terminationStatus: status,
        standardOutput: Data(output.utf8),
        standardError: Data(error.utf8)
    )
}

private func coreVoidResultSucceeded(
    _ result: Result<Void, WindowPinningError>
) -> Bool {
    if case .success = result { return true }
    return false
}

private func coreVoidResultFailure(
    _ result: Result<Void, WindowPinningError>
) -> WindowPinningError? {
    guard case .failure(let error) = result else { return nil }
    return error
}

private final class CoreMutableValidityChecker: WindowValidityChecking {
    var isValid: Bool

    init(isValid: Bool) {
        self.isValid = isValid
    }

    func isValid(window: FocusedWindow) -> Bool { isValid }
}

private final class CoreFakeWindowVisibilityController: WindowVisibilityControlling {
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

private final class CoreVisibilityValidityChecker: WindowValidityChecking {
    var invalidIdentities: Set<WindowIdentity> = []

    func isValid(window: FocusedWindow) -> Bool {
        !invalidIdentities.contains(window.identity)
    }
}

private func coreVisibilitySummary(
    _ result: Result<PinnedWindowSummary, WindowVisibilityError>
) -> PinnedWindowSummary? {
    guard case .success(let summary) = result else { return nil }
    return summary
}

private func coreVisibilityError(
    _ result: Result<PinnedWindowSummary, WindowVisibilityError>
) -> WindowVisibilityError? {
    guard case .failure(let error) = result else { return nil }
    return error
}

private func makeWindow(pid: pid_t, hash: CFHashCode, title: String) -> FocusedWindow {
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
