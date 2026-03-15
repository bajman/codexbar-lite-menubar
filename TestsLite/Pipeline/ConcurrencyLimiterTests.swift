// TestsLite/Pipeline/ConcurrencyLimiterTests.swift
import Testing
@testable import CodexBarCore

@Suite("ConcurrencyLimiter")
struct ConcurrencyLimiterTests {

    @Test("allows up to limit concurrent acquisitions")
    func allowsUpToLimit() async {
        let limiter = ConcurrencyLimiter(limit: 2)
        await limiter.acquire()
        await limiter.acquire()
        await limiter.release()
        await limiter.release()
    }

    @Test("blocks third acquire until release")
    func blocksOverLimit() async {
        let limiter = ConcurrencyLimiter(limit: 1)
        await limiter.acquire()

        let flag = Flag()
        let task = Task {
            await limiter.acquire()
            await flag.set(true)
        }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await flag.value == false)

        await limiter.release()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await flag.value == true)

        await limiter.release()
        task.cancel()
    }
}

private actor Flag {
    var value: Bool = false
    func set(_ v: Bool) { value = v }
}
