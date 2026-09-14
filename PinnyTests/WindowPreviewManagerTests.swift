import CoreGraphics
import Foundation
import Testing
@testable import Pinny

@Suite("Window preview manager")
@MainActor
struct WindowPreviewManagerTests {
    @Test
    func testUniqueProcessAndBoundsSelectionStartsThatWindow() async throws {
        let capturer = FakePreviewCapturer()
        let target = makePreviewWindow(
            id: 10,
            pid: 100,
            title: "Docs",
            frame: CGRect(x: 20, y: 30, width: 800, height: 600)
        )
        let sibling = makePreviewWindow(
            id: 11,
            pid: 100,
            title: "Other",
            frame: CGRect(x: 900, y: 30, width: 400, height: 300)
        )
        capturer.windowsResult = .success([target, sibling])
        let manager = WindowPreviewManager(capture: capturer)

        manager.begin(selection: PreviewWindowSelection(
            processIdentifier: 100,
            title: "Docs",
            frame: CGRect(x: 21, y: 29, width: 801, height: 599)
        ))

        #expect(await waitUntil { capturer.startedSessions.count == 1 })
        #expect(capturer.startedSessions.first?.window == target)
    }

    @Test
    func testDuplicateTitleAndBoundsNeverGuessesFirstMatch() async {
        let capturer = FakePreviewCapturer()
        let frame = CGRect(x: 10, y: 10, width: 500, height: 400)
        let first = makePreviewWindow(id: 20, pid: 200, title: "Same", frame: frame)
        let second = makePreviewWindow(id: 21, pid: 200, title: "Same", frame: frame)
        capturer.windowsResult = .success([first, second])
        let manager = WindowPreviewManager(capture: capturer)

        manager.begin(selection: PreviewWindowSelection(
            processIdentifier: 200,
            title: "Same",
            frame: frame
        ))

        #expect(await waitUntil {
            if case .choosing(let windows) = manager.state {
                return windows == [first, second]
            }
            return false
        })
        #expect(capturer.startedSessions.isEmpty)
    }

    @Test
    func testSelectionWithoutMatchingProcessShowsChooser() async {
        let capturer = FakePreviewCapturer()
        let first = makePreviewWindow(id: 30, pid: 300, title: "A")
        let second = makePreviewWindow(id: 31, pid: 301, title: "B")
        capturer.windowsResult = .success([first, second])
        let manager = WindowPreviewManager(capture: capturer)

        manager.begin(selection: PreviewWindowSelection(
            processIdentifier: 999,
            title: "Missing",
            frame: CGRect(x: 0, y: 0, width: 100, height: 100)
        ))

        #expect(await waitUntil {
            if case .choosing(let windows) = manager.state {
                return windows == [first, second]
            }
            return false
        })
        #expect(capturer.startedSessions.isEmpty)
    }

    @Test
    func testNoShareableWindowsFailsTruthfully() async {
        let capturer = FakePreviewCapturer()
        capturer.windowsResult = .success([])
        let manager = WindowPreviewManager(capture: capturer)

        manager.begin(selection: nil)

        #expect(await waitUntil {
            manager.state == .failed("No shareable windows are available.")
        })
    }

    @Test
    func testReturnedStartWithoutReadyStaysStarting() async throws {
        let capturer = FakePreviewCapturer()
        let window = makePreviewWindow(id: 40, pid: 400, title: "Only")
        capturer.windowsResult = .success([window])
        let manager = WindowPreviewManager(capture: capturer)

        manager.begin(selection: PreviewWindowSelection(
            processIdentifier: 400,
            title: "Only",
            frame: nil
        ))

        #expect(await waitUntil { capturer.startedSessions.count == 1 })
        #expect(manager.state == .starting(window))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(manager.state == .starting(window))
        #expect(manager.state.activeWindow == nil)
    }

    @Test
    func testReadyCallbackActivatesPreview() async throws {
        let capturer = FakePreviewCapturer()
        let window = makePreviewWindow(id: 41, pid: 401, title: "Only")
        capturer.windowsResult = .success([window])
        let manager = WindowPreviewManager(capture: capturer)

        manager.begin(selection: nil)
        #expect(await waitUntil {
            if case .choosing(let windows) = manager.state {
                return windows == [window]
            }
            return false
        })
        manager.select(window)
        #expect(await waitUntil { capturer.startedSessions.count == 1 })
        #expect(manager.state == .starting(window))

        let sessionID = try #require(capturer.startedSessions.first?.sessionID)
        capturer.fireReady(for: sessionID)

        #expect(await waitUntil { manager.state == .active(window) })
    }

    @Test
    func testStartThrowNeverMarksActive() async throws {
        let capturer = FakePreviewCapturer()
        let window = makePreviewWindow(id: 42, pid: 402, title: "Only")
        capturer.windowsResult = .success([window])
        capturer.startError = WindowPreviewError.windowUnavailable
        let manager = WindowPreviewManager(capture: capturer)

        manager.begin(selection: PreviewWindowSelection(
            processIdentifier: 402,
            title: "Only",
            frame: nil
        ))

        #expect(await waitUntil { capturer.startedSessions.count == 1 })
        #expect(await waitUntil {
            if case .failed = manager.state { return true }
            return false
        })
        #expect(manager.state.activeWindow == nil)
        let sessionID = try #require(capturer.startedSessions.first?.sessionID)
        #expect(await waitUntil { capturer.stoppedSessionIDs.contains(sessionID) })
    }

    @Test
    func testStopDuringEnumerationIgnoresLateCandidates() async {
        let capturer = FakePreviewCapturer()
        capturer.suspendsEnumeration = true
        let manager = WindowPreviewManager(capture: capturer)

        manager.begin(selection: nil)
        #expect(manager.state == .loading)
        #expect(await waitUntil { capturer.availableWindowsCalls == 1 })

        manager.stop()
        #expect(manager.state == .idle)

        capturer.resumeEnumeration(
            at: 0,
            with: .success([makePreviewWindow(id: 50, pid: 500, title: "Late")])
        )
        try? await Task.sleep(for: .milliseconds(50))

        #expect(manager.state == .idle)
        #expect(capturer.startedSessions.isEmpty)
    }

    @Test
    func testStaleEnumerationAfterNewerEnumerationDoesNotRegressState() async {
        let capturer = FakePreviewCapturer()
        capturer.suspendsEnumeration = true
        let older = makePreviewWindow(id: 55, pid: 550, title: "Older")
        let newer = makePreviewWindow(id: 56, pid: 551, title: "Newer")
        let manager = WindowPreviewManager(capture: capturer)

        manager.begin(selection: nil)
        #expect(await waitUntil { capturer.availableWindowsCalls == 1 })
        manager.begin(selection: nil)
        #expect(await waitUntil { capturer.availableWindowsCalls == 2 })

        capturer.resumeEnumeration(at: 1, with: .success([newer]))
        #expect(await waitUntil { manager.state == .choosing([newer]) })

        capturer.resumeEnumeration(at: 0, with: .success([older]))
        try? await Task.sleep(for: .milliseconds(50))

        #expect(manager.state == .choosing([newer]))
        #expect(capturer.startedSessions.isEmpty)
    }

    @Test
    func testStopImmediatelyAfterSelectNeverStartsSession() async {
        let capturer = FakePreviewCapturer()
        let first = makePreviewWindow(id: 57, pid: 570, title: "A")
        let second = makePreviewWindow(id: 58, pid: 570, title: "B")
        capturer.windowsResult = .success([first, second])
        let manager = WindowPreviewManager(capture: capturer)

        manager.begin(selection: nil)
        #expect(await waitUntil { manager.state == .choosing([first, second]) })

        manager.select(first)
        manager.stop()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(capturer.startedSessions.isEmpty)
        #expect(manager.state == .idle)
    }

    @Test
    func testStopImmediatelyAfterBeginNeverEnumerates() async {
        let capturer = FakePreviewCapturer()
        let manager = WindowPreviewManager(capture: capturer)

        manager.begin(selection: nil)
        manager.stop()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(capturer.availableWindowsCalls == 0)
        #expect(manager.state == .idle)
    }

    @Test
    func testStopDuringStartIgnoresLateReadyAndError() async throws {
        let capturer = FakePreviewCapturer()
        capturer.suspendsStart = true
        let window = makePreviewWindow(id: 60, pid: 600, title: "Only")
        capturer.windowsResult = .success([window])
        let manager = WindowPreviewManager(capture: capturer)

        manager.begin(selection: PreviewWindowSelection(
            processIdentifier: 600,
            title: "Only",
            frame: nil
        ))
        #expect(await waitUntil { capturer.startedSessions.count == 1 })
        #expect(manager.state == .starting(window))
        let sessionID = try #require(capturer.startedSessions.first?.sessionID)

        manager.stop()
        #expect(manager.state == .idle)
        #expect(await waitUntil { capturer.stoppedSessionIDs.contains(sessionID) })

        capturer.resumeStart(of: sessionID)
        try? await Task.sleep(for: .milliseconds(30))
        capturer.fireReady(for: sessionID)
        capturer.fireEnd(for: sessionID, reason: "late failure")
        try? await Task.sleep(for: .milliseconds(30))

        #expect(manager.state == .idle)
    }

    @Test
    func testStaleEndFromOldSessionKeepsNewActivePreview() async throws {
        let capturer = FakePreviewCapturer()
        let first = makePreviewWindow(id: 70, pid: 700, title: "First")
        let second = makePreviewWindow(id: 71, pid: 701, title: "Second")
        capturer.windowsResult = .success([first])
        let manager = WindowPreviewManager(capture: capturer)

        manager.begin(selection: PreviewWindowSelection(
            processIdentifier: 700,
            title: "First",
            frame: nil
        ))
        #expect(await waitUntil { capturer.startedSessions.count == 1 })
        let firstSession = try #require(capturer.startedSessions.first?.sessionID)
        capturer.fireReady(for: firstSession)
        #expect(await waitUntil { manager.state == .active(first) })

        capturer.windowsResult = .success([second])
        manager.begin(selection: PreviewWindowSelection(
            processIdentifier: 701,
            title: "Second",
            frame: nil
        ))
        #expect(await waitUntil { capturer.startedSessions.count == 2 })
        let secondSession = try #require(capturer.startedSessions.last?.sessionID)
        capturer.fireReady(for: secondSession)
        #expect(await waitUntil { manager.state == .active(second) })

        capturer.fireEnd(for: firstSession, reason: "stale callback")
        try? await Task.sleep(for: .milliseconds(30))

        #expect(manager.state == .active(second))
    }

    @Test
    func testSelectingWindowOutsideOfferedChoicesDoesNothing() async {
        let capturer = FakePreviewCapturer()
        let first = makePreviewWindow(id: 80, pid: 800, title: "A")
        let second = makePreviewWindow(id: 81, pid: 800, title: "B")
        let outsider = makePreviewWindow(id: 82, pid: 800, title: "C")
        capturer.windowsResult = .success([first, second])
        let manager = WindowPreviewManager(capture: capturer)

        manager.begin(selection: nil)
        #expect(await waitUntil { manager.state == .choosing([first, second]) })

        manager.select(outsider)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(capturer.startedSessions.isEmpty)
        #expect(manager.state == .choosing([first, second]))

        manager.select(first)
        #expect(await waitUntil { capturer.startedSessions.count == 1 })
        #expect(manager.state == .starting(first))
    }

    @Test
    func testNormalPreviewCloseReturnsToIdle() async throws {
        let capturer = FakePreviewCapturer()
        let window = makePreviewWindow(id: 90, pid: 900, title: "Only")
        capturer.windowsResult = .success([window])
        let manager = WindowPreviewManager(capture: capturer)

        manager.begin(selection: PreviewWindowSelection(
            processIdentifier: 900,
            title: "Only",
            frame: nil
        ))
        #expect(await waitUntil { capturer.startedSessions.count == 1 })
        let sessionID = try #require(capturer.startedSessions.first?.sessionID)
        capturer.fireReady(for: sessionID)
        #expect(await waitUntil { manager.state == .active(window) })

        capturer.fireEnd(for: sessionID)

        #expect(await waitUntil { manager.state == .idle })
        #expect(await waitUntil { capturer.stoppedSessionIDs.contains(sessionID) })
    }

    @Test
    func testCaptureFailureReportsErrorAndStopsSession() async throws {
        let capturer = FakePreviewCapturer()
        let window = makePreviewWindow(id: 91, pid: 901, title: "Only")
        capturer.windowsResult = .success([window])
        let manager = WindowPreviewManager(capture: capturer)

        manager.begin(selection: PreviewWindowSelection(
            processIdentifier: 901,
            title: "Only",
            frame: nil
        ))
        #expect(await waitUntil { capturer.startedSessions.count == 1 })
        let sessionID = try #require(capturer.startedSessions.first?.sessionID)
        capturer.fireReady(for: sessionID)
        #expect(await waitUntil { manager.state == .active(window) })

        capturer.fireEnd(for: sessionID, reason: "The window stopped sharing frames.")

        #expect(await waitUntil {
            manager.state == .failed("The window stopped sharing frames.")
        })
        #expect(await waitUntil { capturer.stoppedSessionIDs.contains(sessionID) })
    }

    @Test
    func testCanStopCoversInterruptibleStates() {
        let window = makePreviewWindow(id: 92, pid: 902, title: "W")
        #expect(WindowPreviewState.idle.canStop == false)
        #expect(WindowPreviewState.failed("x").canStop == false)
        #expect(WindowPreviewState.loading.canStop)
        #expect(WindowPreviewState.choosing([window]).canStop)
        #expect(WindowPreviewState.starting(window).canStop)
        #expect(WindowPreviewState.active(window).canStop)
    }

    private func makePreviewWindow(
        id: CGWindowID,
        pid: pid_t,
        title: String?,
        frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600)
    ) -> PreviewWindow {
        PreviewWindow(
            id: id,
            processIdentifier: pid,
            applicationName: "Safari",
            title: title,
            frame: frame
        )
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}

@MainActor
private final class FakePreviewCapturer: WindowPreviewCapturing {
    struct StartedSession {
        let sessionID: UUID
        let window: PreviewWindow
    }

    private(set) var availableWindowsCalls = 0
    private(set) var startedSessions: [StartedSession] = []
    private(set) var stoppedSessionIDs: [UUID] = []

    var windowsResult: Result<[PreviewWindow], Error> = .success([])
    var suspendsEnumeration = false
    var startError: Error?
    var suspendsStart = false

    private var enumerationContinuations: [CheckedContinuation<[PreviewWindow], Error>] = []
    private var startContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var readyCallbacks: [UUID: () -> Void] = [:]
    private var endCallbacks: [UUID: (String?) -> Void] = [:]

    func availableWindows() async throws -> [PreviewWindow] {
        availableWindowsCalls += 1
        if suspendsEnumeration {
            return try await withCheckedThrowingContinuation { continuation in
                enumerationContinuations.append(continuation)
            }
        }
        return try windowsResult.get()
    }

    func start(
        window: PreviewWindow,
        sessionID: UUID,
        onReady: @escaping () -> Void,
        onEnd: @escaping (String?) -> Void
    ) async throws {
        startedSessions.append(StartedSession(sessionID: sessionID, window: window))
        readyCallbacks[sessionID] = onReady
        endCallbacks[sessionID] = onEnd
        if let startError {
            throw startError
        }
        if suspendsStart {
            try await withCheckedThrowingContinuation { continuation in
                startContinuations[sessionID] = continuation
            }
        }
    }

    func stop(sessionID: UUID) async {
        stoppedSessionIDs.append(sessionID)
    }

    func resumeEnumeration(
        at index: Int,
        with result: Result<[PreviewWindow], Error>
    ) {
        guard enumerationContinuations.indices.contains(index) else { return }
        let continuation = enumerationContinuations.remove(at: index)
        switch result {
        case .success(let windows):
            continuation.resume(returning: windows)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    func resumeStart(of sessionID: UUID, throwing error: Error? = nil) {
        guard let continuation = startContinuations.removeValue(forKey: sessionID) else {
            return
        }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    func fireReady(for sessionID: UUID) {
        readyCallbacks[sessionID]?()
    }

    func fireEnd(for sessionID: UUID, reason: String? = nil) {
        endCallbacks[sessionID]?(reason)
    }
}
