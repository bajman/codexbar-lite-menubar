import Testing
import Foundation
@testable import CodexBarCore

@Suite("CoalescingEngine")
struct CoalescingEngineTests {
    @Test("merges requests by OR-ing flags and taking highest priority")
    func mergeRequests() {
        var engine = CoalescingEngine()
        engine.mergeRefreshRequest(RefreshRequest(forceTokenUsage: true, priority: .p2))
        engine.mergeRefreshRequest(RefreshRequest(forceStatusChecks: true, priority: .p0))
        let merged = engine.drainPendingRequest()
        #expect(merged?.forceTokenUsage == true)
        #expect(merged?.forceStatusChecks == true)
        #expect(merged?.priority == .p0)
    }

    @Test("drain returns nil when empty")
    func drainEmpty() {
        var engine = CoalescingEngine()
        #expect(engine.drainPendingRequest() == nil)
    }

    @Test("shouldSkip returns true within minimum interval")
    func minimumInterval() {
        var engine = CoalescingEngine()
        engine.recordCompletion(provider: .claude, kind: .quota)
        let skip = engine.shouldSkip(provider: .claude, kind: .quota, priority: .p2)
        #expect(skip == true)
    }

    @Test("shouldSkip returns false for P0")
    func p0Bypasses() {
        var engine = CoalescingEngine()
        engine.recordCompletion(provider: .claude, kind: .quota)
        let skip = engine.shouldSkip(provider: .claude, kind: .quota, priority: .p0)
        #expect(skip == false)
    }

    @Test("shouldSkip returns false when no prior completion")
    func noPriorCompletion() {
        let engine = CoalescingEngine()
        let skip = engine.shouldSkip(provider: .claude, kind: .quota, priority: .p2)
        #expect(skip == false)
    }
}
