import Testing
import Foundation
@testable import CodexBarCore

/// Thread-safe mutable date box for use in `@Sendable` closures.
final class DateBox: @unchecked Sendable {
    var value: Date
    init(_ value: Date) { self.value = value }
}

@Suite("AdaptiveRefreshTimer")
struct AdaptiveRefreshTimerTests {
    @Test("starts in idle state with 15min interval")
    func initialState() async {
        let timer = AdaptiveRefreshTimer()
        let interval = await timer.currentInterval
        #expect(interval == .seconds(900))
        let state = await timer.state
        #expect(state == .idle)
    }

    @Test("transitions to active on FSEvent")
    func transitionsToActive() async {
        let timer = AdaptiveRefreshTimer()
        await timer.recordFSEvent()
        let state = await timer.state
        #expect(state == .active)
        let interval = await timer.currentInterval
        #expect(interval == .seconds(120))
    }

    @Test("transitions to idle after 15-60 min without events")
    func transitionsToIdle() async {
        let baseDate = Date()
        let box = DateBox(baseDate)
        let timer = AdaptiveRefreshTimer(nowProvider: { box.value })

        await timer.recordFSEvent()  // records at baseDate
        box.value = baseDate.addingTimeInterval(1800)  // 30 min later
        await timer.evaluateState()

        let state = await timer.state
        #expect(state == .idle)
    }

    @Test("transitions to deepIdle after 1+ hour without events")
    func transitionsToDeepIdle() async {
        let baseDate = Date()
        let box = DateBox(baseDate)
        let timer = AdaptiveRefreshTimer(nowProvider: { box.value })

        await timer.recordFSEvent()
        box.value = baseDate.addingTimeInterval(3700)  // 1hr+ later
        await timer.evaluateState()

        let state = await timer.state
        #expect(state == .deepIdle)
        let interval = await timer.currentInterval
        #expect(interval == .seconds(1800))
    }

    @Test("pause and resume work")
    func pauseResume() async {
        let timer = AdaptiveRefreshTimer()
        #expect(await timer.isPaused == false)
        await timer.pause()
        #expect(await timer.isPaused == true)
        await timer.resume()
        #expect(await timer.isPaused == false)
    }
}
