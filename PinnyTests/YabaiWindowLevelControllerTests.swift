import ApplicationServices
import CoreGraphics
import Testing
@testable import Pinny

@Suite("Verified yabai window-level controller")
struct YabaiWindowLevelControllerTests {
    @Test
    func verifiedPinReturnsTypedRestorationToken() {
        let service = FakeYabaiWindowService(
            windowID: 101,
            ownerProcessIdentifier: 501,
            subLayer: "normal"
        )
        let controller = YabaiWindowLevelController(service: service)

        let result = controller.pin(window: makeYabaiTestWindow(pid: 501, hash: 1))

        guard case .success(let token) = result else {
            Issue.record("Expected a verified pin, got \(result)")
            return
        }
        #expect(token.yabaiState == YabaiWindowRestorationState(
            ownerProcessIdentifier: 501,
            windowID: 101,
            originalSubLayer: "normal"
        ))
        #expect(service.records[101]?.subLayer == "above")
        #expect(service.setCalls == [SetSubLayerCall(windowID: 101, subLayer: "above")])
    }

    @Test
    func unpinRestoresTheExactOriginalSubLayer() {
        let service = FakeYabaiWindowService(
            windowID: 102,
            ownerProcessIdentifier: 502,
            subLayer: "below"
        )
        let controller = YabaiWindowLevelController(service: service)
        let window = makeYabaiTestWindow(pid: 502, hash: 2)
        guard case .success(let token) = controller.pin(window: window) else {
            Issue.record("Pin setup failed")
            return
        }

        let result = controller.unpin(window: window, token: token)

        guard case .success = result else {
            Issue.record("Expected restoration to succeed, got \(result)")
            return
        }
        #expect(service.records[102]?.subLayer == "below")
        #expect(service.setCalls == [
            SetSubLayerCall(windowID: 102, subLayer: "above"),
            SetSubLayerCall(windowID: 102, subLayer: "below")
        ])
    }

    @Test
    func pinRejectsAnOwnerMismatchBeforeMutation() {
        let service = FakeYabaiWindowService(
            windowID: 103,
            ownerProcessIdentifier: 999,
            subLayer: "normal"
        )
        let controller = YabaiWindowLevelController(service: service)

        let result = controller.pin(window: makeYabaiTestWindow(pid: 503, hash: 3))

        #expect(result == .failure(.ownerMismatch(expected: 503, actual: 999)))
        #expect(service.setCalls.isEmpty)
    }

    @Test
    func recycledWindowIDIsNeverMutatedDuringRestoreOrMaintenance() {
        let service = FakeYabaiWindowService(
            windowID: 104,
            ownerProcessIdentifier: 504,
            subLayer: "normal"
        )
        let controller = YabaiWindowLevelController(service: service)
        let window = makeYabaiTestWindow(pid: 504, hash: 4)
        guard case .success(let token) = controller.pin(window: window) else {
            Issue.record("Pin setup failed")
            return
        }
        service.records[104] = YabaiWindowRecord(
            windowID: 104,
            ownerProcessIdentifier: 777,
            subLayer: "normal"
        )

        let restoreResult = controller.unpin(window: window, token: token)
        let maintenanceResult = controller.maintain(window: window, token: token)

        guard case .failure(let restoreError) = restoreResult else {
            Issue.record("Expected recycled-ID restoration to fail safely")
            return
        }
        #expect(restoreError == .ownerMismatch(expected: 504, actual: 777))
        #expect(maintenanceResult == .targetGone)
        #expect(service.setCalls == [SetSubLayerCall(windowID: 104, subLayer: "above")])
    }

    @Test
    func pinPropagatesMutationFailureAndDoesNotReturnAToken() {
        let service = FakeYabaiWindowService(
            windowID: 105,
            ownerProcessIdentifier: 505,
            subLayer: "normal"
        )
        service.setResults = [.failure(.advancedHelperUnavailable("mutation denied"))]
        let controller = YabaiWindowLevelController(service: service)

        let result = controller.pin(window: makeYabaiTestWindow(pid: 505, hash: 5))

        #expect(result == .failure(.advancedHelperUnavailable("mutation denied")))
        #expect(service.records[105]?.subLayer == "normal")
        #expect(service.setCalls == [SetSubLayerCall(windowID: 105, subLayer: "above")])
    }

    @Test
    func pinRejectsSuccessfulCommandWhenReadbackDoesNotVerify() {
        let service = FakeYabaiWindowService(
            windowID: 106,
            ownerProcessIdentifier: 506,
            subLayer: "normal"
        )
        service.mutateRecordAfterSuccessfulSet = false
        let controller = YabaiWindowLevelController(service: service)

        let result = controller.pin(window: makeYabaiTestWindow(pid: 506, hash: 6))

        #expect(result == .failure(.verificationFailed(expected: "above", actual: "normal")))
        #expect(service.records[106]?.subLayer == "normal")
    }

    @Test
    func sameWindowServerIDMatchesAcrossDifferentAXIdentities() {
        let service = FakeYabaiWindowService(
            windowID: 107,
            ownerProcessIdentifier: 507,
            subLayer: "normal"
        )
        let controller = YabaiWindowLevelController(service: service)
        let original = makeYabaiTestWindow(pid: 507, hash: 7)
        let replacementAXReference = makeYabaiTestWindow(pid: 507, hash: 8)
        guard case .success(let token) = controller.pin(window: original) else {
            Issue.record("Pin setup failed")
            return
        }

        #expect(original.identity != replacementAXReference.identity)
        #expect(controller.representsSameWindow(
            candidate: replacementAXReference,
            pinnedWindow: original,
            token: token
        ))
    }

    @Test
    func maintenanceReappliesAboveAfterSubLayerDrift() {
        let service = FakeYabaiWindowService(
            windowID: 108,
            ownerProcessIdentifier: 508,
            subLayer: "normal"
        )
        let controller = YabaiWindowLevelController(service: service)
        let window = makeYabaiTestWindow(pid: 508, hash: 9)
        guard case .success(let token) = controller.pin(window: window) else {
            Issue.record("Pin setup failed")
            return
        }
        service.records[108] = YabaiWindowRecord(
            windowID: 108,
            ownerProcessIdentifier: 508,
            subLayer: "normal"
        )

        let result = controller.maintain(window: window, token: token)

        #expect(result == .reapplied)
        #expect(service.records[108]?.subLayer == "above")
        #expect(service.setCalls == [
            SetSubLayerCall(windowID: 108, subLayer: "above"),
            SetSubLayerCall(windowID: 108, subLayer: "above")
        ])
    }

    @Test
    func staleTargetClearsManagerStateWithoutFurtherMutation() {
        let service = FakeYabaiWindowService(
            windowID: 109,
            ownerProcessIdentifier: 509,
            subLayer: "normal"
        )
        let controller = YabaiWindowLevelController(service: service)
        let manager = WindowPinManager(levelController: controller)
        let window = makeYabaiTestWindow(pid: 509, hash: 10)
        _ = manager.toggle(window: window)
        service.records.removeValue(forKey: 109)

        let maintenance = manager.removeStaleStateIfNeeded()

        #expect(maintenance == .targetGone)
        #expect(manager.pinnedWindow == nil)
        #expect(service.setCalls == [SetSubLayerCall(windowID: 109, subLayer: "above")])
    }

    @Test
    func failedUnpinRetainsManagerStateAndRetriesRestore() {
        let service = FakeYabaiWindowService(
            windowID: 110,
            ownerProcessIdentifier: 510,
            subLayer: "normal"
        )
        let controller = YabaiWindowLevelController(service: service)
        let manager = WindowPinManager(levelController: controller)
        let window = makeYabaiTestWindow(pid: 510, hash: 11)
        _ = manager.toggle(window: window)
        service.setResults = [
            .failure(.advancedHelperUnavailable("restore blocked")),
            .failure(.advancedHelperUnavailable("restore blocked"))
        ]

        let result = manager.toggle(window: window)

        #expect(result == .unable(.restorationFailed("restore blocked")))
        #expect(manager.pinnedWindow?.restorationToken.yabaiState?.windowID == 110)
        #expect(service.records[110]?.subLayer == "above")
        #expect(service.setCalls == [
            SetSubLayerCall(windowID: 110, subLayer: "above"),
            SetSubLayerCall(windowID: 110, subLayer: "normal"),
            SetSubLayerCall(windowID: 110, subLayer: "normal")
        ])
    }

    @Test
    func switchingWindowsRestoresFirstBeforePinningSecond() {
        let service = FakeYabaiWindowService(
            windowID: 111,
            ownerProcessIdentifier: 511,
            subLayer: "normal"
        )
        service.records[112] = YabaiWindowRecord(
            windowID: 112,
            ownerProcessIdentifier: 511,
            subLayer: "below"
        )
        service.windowIDResults = [.success(111), .success(112), .success(112)]
        let manager = WindowPinManager(
            levelController: YabaiWindowLevelController(service: service)
        )
        let first = makeYabaiTestWindow(pid: 511, hash: 12, title: "First")
        let second = makeYabaiTestWindow(pid: 511, hash: 13, title: "Second")
        _ = manager.toggle(window: first)

        let result = manager.toggle(window: second)

        #expect(result == .pinned(PinnedWindowSummary(
            applicationName: "Test App",
            windowTitle: "Second"
        )))
        #expect(manager.pinnedWindow?.restorationToken.yabaiState?.windowID == 112)
        #expect(service.records[111]?.subLayer == "normal")
        #expect(service.records[112]?.subLayer == "above")
        #expect(service.setCalls == [
            SetSubLayerCall(windowID: 111, subLayer: "above"),
            SetSubLayerCall(windowID: 111, subLayer: "normal"),
            SetSubLayerCall(windowID: 112, subLayer: "above")
        ])
    }

    @Test
    func switchingWindowsStopsIfFirstWindowCannotBeRestored() {
        let service = FakeYabaiWindowService(
            windowID: 113,
            ownerProcessIdentifier: 513,
            subLayer: "normal"
        )
        service.records[114] = YabaiWindowRecord(
            windowID: 114,
            ownerProcessIdentifier: 513,
            subLayer: "normal"
        )
        service.windowIDResults = [.success(113), .success(114)]
        let manager = WindowPinManager(
            levelController: YabaiWindowLevelController(service: service)
        )
        _ = manager.toggle(window: makeYabaiTestWindow(pid: 513, hash: 14, title: "First"))
        service.setResults = [
            .failure(.advancedHelperUnavailable("restore blocked")),
            .failure(.advancedHelperUnavailable("restore blocked"))
        ]

        let result = manager.toggle(
            window: makeYabaiTestWindow(pid: 513, hash: 15, title: "Second")
        )

        #expect(result == .unable(.restorationFailed("restore blocked")))
        #expect(manager.pinnedWindow?.restorationToken.yabaiState?.windowID == 113)
        #expect(service.records[113]?.subLayer == "above")
        #expect(service.records[114]?.subLayer == "normal")
        #expect(!service.setCalls.contains(
            SetSubLayerCall(windowID: 114, subLayer: "above")
        ))
    }
}

private struct SetSubLayerCall: Equatable {
    let windowID: CGWindowID
    let subLayer: String
}

private final class FakeYabaiWindowService: YabaiWindowServicing {
    var defaultWindowID: CGWindowID
    var windowIDResults: [Result<CGWindowID, WindowPinningError>] = []
    var records: [CGWindowID: YabaiWindowRecord]
    var recordResults: [Result<YabaiWindowRecord, WindowPinningError>] = []
    var setResults: [Result<Void, WindowPinningError>] = []
    var mutateRecordAfterSuccessfulSet = true
    private(set) var setCalls: [SetSubLayerCall] = []

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
        setCalls.append(SetSubLayerCall(windowID: windowID, subLayer: subLayer))
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

private func makeYabaiTestWindow(
    pid: pid_t,
    hash: CFHashCode,
    title: String = "Document"
) -> FocusedWindow {
    FocusedWindow(
        identity: WindowIdentity(processIdentifier: pid, accessibilityElementHash: hash),
        applicationName: "Test App",
        applicationBundleIdentifier: "com.example.test-app",
        title: title,
        role: "AXWindow",
        subrole: "AXStandardWindow",
        element: AXUIElementCreateSystemWide()
    )
}
