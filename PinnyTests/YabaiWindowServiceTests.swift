import CoreGraphics
import Foundation
import Testing
@testable import Pinny

@Suite("yabai command service")
struct YabaiWindowServiceTests {
    @Test
    func windowQueryParsesTheVerifiedFields() {
        let runner = FakeYabaiCommandRunner(results: [
            .success(commandResult(
                output: #"{"id":201,"pid":601,"sub-layer":"above"}"#
            ))
        ])
        let service = makeService(runner: runner)

        let result = service.windowRecord(for: 201)

        #expect(result == .success(YabaiWindowRecord(
            windowID: 201,
            ownerProcessIdentifier: 601,
            subLayer: "above"
        )))
        #expect(runner.invocations == [YabaiInvocation(
            executablePath: "/tmp/pinny-tests-yabai",
            arguments: ["-m", "query", "--windows", "--window", "201"]
        )])
    }

    @Test
    func mismatchedQueryIdentifierIsTreatedAsStale() {
        let runner = FakeYabaiCommandRunner(results: [
            .success(commandResult(
                output: #"{"id":999,"pid":602,"sub-layer":"normal"}"#
            ))
        ])
        let service = makeService(runner: runner)

        #expect(service.windowRecord(for: 202) == .failure(.staleWindow))
    }

    @Test
    func mutationUsesNarrowWindowAndSubLayerArguments() {
        let runner = FakeYabaiCommandRunner(results: [.success(commandResult())])
        let service = makeService(runner: runner)

        let result = service.setSubLayer("below", for: 203)

        guard case .success = result else {
            Issue.record("Expected the helper mutation to succeed, got \(result)")
            return
        }
        #expect(runner.invocations == [YabaiInvocation(
            executablePath: "/tmp/pinny-tests-yabai",
            arguments: ["-m", "window", "203", "--sub-layer", "below"]
        )])
    }

    @Test
    func unknownSubLayerIsRejectedWithoutLaunchingHelper() {
        let runner = FakeYabaiCommandRunner(results: [])
        let service = makeService(runner: runner)

        let result = service.setSubLayer("ceiling", for: 204)

        guard case .failure(let error) = result else {
            Issue.record("Expected the unknown sub-layer to be rejected")
            return
        }
        #expect(error == .targetRejected(
            "Pinny refused an unknown window sub-layer."
        ))
        #expect(runner.invocations.isEmpty)
    }

    @Test
    func failedHelperCommandSurfacesItsDiagnostic() {
        let runner = FakeYabaiCommandRunner(results: [
            .success(commandResult(status: 1, error: "scripting addition not loaded\n"))
        ])
        let service = makeService(runner: runner)

        let result = service.windowRecord(for: 205)

        #expect(result == .failure(.advancedHelperUnavailable(
            "scripting addition not loaded"
        )))
    }

    @Test
    func missingExecutableFailsWithoutLaunchingAnything() {
        let runner = FakeYabaiCommandRunner(results: [])
        let service = YabaiWindowService(executableURL: nil, runner: runner)

        let result = service.windowRecord(for: 206)

        guard case .failure(.advancedHelperUnavailable(let reason)) = result else {
            Issue.record("Expected the missing-helper failure, got \(result)")
            return
        }
        #expect(reason.contains("did not find it"))
        #expect(runner.invocations.isEmpty)
    }

    @Test
    func malformedJSONCannotVerifyAWindow() {
        let runner = FakeYabaiCommandRunner(results: [
            .success(commandResult(output: "not json"))
        ])
        let service = makeService(runner: runner)

        let result = service.windowRecord(for: 207)

        #expect(result == .failure(.advancedHelperUnavailable(
            "yabai returned invalid JSON while Pinny verified the target window."
        )))
    }
}

private struct YabaiInvocation: Equatable {
    let executablePath: String
    let arguments: [String]
}

private final class FakeYabaiCommandRunner: YabaiCommandRunning {
    var results: [Result<YabaiCommandResult, Error>]
    private(set) var invocations: [YabaiInvocation] = []

    init(results: [Result<YabaiCommandResult, Error>]) {
        self.results = results
    }

    func run(
        executableURL: URL,
        arguments: [String]
    ) -> Result<YabaiCommandResult, Error> {
        invocations.append(YabaiInvocation(
            executablePath: executableURL.path,
            arguments: arguments
        ))
        guard !results.isEmpty else {
            return .failure(FakeYabaiRunnerError.noQueuedResult)
        }
        return results.removeFirst()
    }
}

private enum FakeYabaiRunnerError: Error {
    case noQueuedResult
}

private func makeService(runner: FakeYabaiCommandRunner) -> YabaiWindowService {
    YabaiWindowService(
        executableURL: URL(fileURLWithPath: "/tmp/pinny-tests-yabai"),
        runner: runner
    )
}

private func commandResult(
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
