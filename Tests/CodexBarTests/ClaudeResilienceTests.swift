import Testing
@testable import CodexBar

@Suite
struct ClaudeResilienceTests {
    @Test
    func suppressesSingleFlakeWhenPriorDataExists() {
        var gate = ConsecutiveFailureGate()
        let firstFailure = gate.shouldSurfaceError(onFailureWithPriorData: true)
        let secondFailure = gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(firstFailure == false)
        #expect(secondFailure == true)
    }

    @Test
    func surfacesFailureWithoutPriorData() {
        var gate = ConsecutiveFailureGate()
        let shouldSurface = gate.shouldSurfaceError(onFailureWithPriorData: false)
        #expect(shouldSurface)
    }

    @Test
    func resetsAfterSuccess() {
        var gate = ConsecutiveFailureGate()
        _ = gate.shouldSurfaceError(onFailureWithPriorData: true)
        gate.recordSuccess()
        let shouldSurface = gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(shouldSurface == false)
    }

    @Test
    func repeatedFailureWithPriorDataKeepsLastSnapshotVisible() {
        var gate = ConsecutiveFailureGate()

        let first = ProviderRefreshFailureResolution.resolve(hadPriorData: true, failureGate: &gate)
        let second = ProviderRefreshFailureResolution.resolve(hadPriorData: true, failureGate: &gate)

        #expect(first.keepSnapshot == true)
        #expect(first.shouldSurfaceError == false)
        #expect(second.keepSnapshot == true)
        #expect(second.shouldSurfaceError == true)
    }

    @Test
    func statusRefreshStateHonorsTTLBackoffAndForceRefresh() {
        let now = Date(timeIntervalSince1970: 1000)
        var state = StatusRefreshState()

        #expect(state.shouldRefresh(now: now, ttl: 600, force: false) == true)

        state.recordSuccess(now: now)
        #expect(state.shouldRefresh(now: now.addingTimeInterval(120), ttl: 600, force: false) == false)
        #expect(state.shouldRefresh(now: now.addingTimeInterval(601), ttl: 600, force: false) == true)

        state.recordFailure(now: now.addingTimeInterval(601), baseBackoff: 60, maxBackoff: 1800)
        #expect(state.shouldRefresh(now: now.addingTimeInterval(620), ttl: 600, force: false) == false)
        #expect(state.shouldRefresh(now: now.addingTimeInterval(662), ttl: 600, force: false) == true)

        state.recordFailure(now: now.addingTimeInterval(662), baseBackoff: 60, maxBackoff: 1800)
        #expect(state.shouldRefresh(now: now.addingTimeInterval(721), ttl: 600, force: false) == false)
        #expect(state.shouldRefresh(now: now.addingTimeInterval(721), ttl: 600, force: true) == true)
    }

    @Test
    func refreshRequestOptionsMergePreservesStrongestFlags() {
        var request = RefreshRequestOptions()

        request.merge(.init(forceTokenUsage: true))
        request.merge(.init(forceStatusChecks: true))

        #expect(request.forceTokenUsage == true)
        #expect(request.forceStatusChecks == true)
    }
}
