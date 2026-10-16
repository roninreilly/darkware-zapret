import Foundation
import Testing
@testable import DarkwareZapret

@Test func certificateOrTransportFailureCannotBecomeReachable() {
    for status: Int32 in [5, 6, 7, 28, 35, 60, 97] {
        #expect(ProbeVerdict.classify(exitStatus: status, httpStatus: 200) == .failed)
    }
}

@Test func HTTPSResultsDistinguishReachabilityFromServerRejection() {
    for status in [200, 204, 301, 302, 307, 308] {
        #expect(ProbeVerdict.classify(exitStatus: 0, httpStatus: status) == .reachable)
    }
    for status in [401, 403, 404, 429, 500, 503] {
        #expect(ProbeVerdict.classify(exitStatus: 0, httpStatus: status) == .inconclusive)
    }
    #expect(ProbeVerdict.classify(exitStatus: 0, httpStatus: 0) == .failed)
}

@Test @MainActor func commandTimeoutDoesNotWaitForLongRunningProcess() async {
    let start = ContinuousClock.now
    do {
        _ = try await CommandRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 0.05)
        Issue.record("Expected command timeout")
    } catch {
        #expect(start.duration(to: .now) < .seconds(3))
    }
}

@Test @MainActor func commandCancellationPropagates() async {
    let task = Task {
        try await CommandRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"])
    }
    try? await Task.sleep(for: .milliseconds(100))
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("Expected cancellation")
    } catch {
        #expect(error is CancellationError)
    }
}
