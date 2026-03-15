import Testing
import Foundation
@testable import CodexBarCore

@Suite("DataPipeline")
struct DataPipelineTests {

    private func makePipeline() async -> DataPipeline {
        let resolver = PricingResolver(networkEnabled: false)
        return DataPipeline(pricingResolver: resolver)
    }

    @Test("enqueue emits event for provider")
    func enqueueAndProcess() async throws {
        let pipeline = await makePipeline()

        // Enqueue a P0 request for Claude — without real credentials this will
        // produce either .quotaUpdated or .error, both are valid.
        await pipeline.enqueue(RefreshRequest(
            providers: [.claude],
            forceQuota: true,
            priority: .p0
        ))

        // Collect the first event with a generous timeout.
        var receivedEvent = false
        let deadline = Date().addingTimeInterval(10)

        for await event in await pipeline.events {
            switch event {
            case .quotaUpdated(let provider, _):
                #expect(provider == .claude)
                receivedEvent = true
            case .error(let provider, _):
                #expect(provider == .claude)
                receivedEvent = true
            default:
                break
            }
            if receivedEvent { break }
            if Date() > deadline { break }
        }

        #expect(receivedEvent, "Expected at least one event from the pipeline")
        await pipeline.shutdown()
    }

    @Test("shutdown terminates event stream")
    func shutdownTerminatesStream() async throws {
        let pipeline = await makePipeline()

        // Shut down immediately.
        await pipeline.shutdown()

        // The event stream should terminate (the for-await loop exits).
        var eventCount = 0
        for await _ in await pipeline.events {
            eventCount += 1
        }
        // After shutdown, no further events should be produced.
        #expect(eventCount == 0)
    }

    @Test("coalesces rapid requests without crashing")
    func coalescesRapidRequests() async throws {
        let pipeline = await makePipeline()

        // Enqueue 3 requests rapidly — they should be merged.
        await pipeline.enqueue(RefreshRequest(providers: [.claude], priority: .p2))
        await pipeline.enqueue(RefreshRequest(providers: [.codex], priority: .p1))
        await pipeline.enqueue(RefreshRequest(providers: [.claude], forceQuota: true, priority: .p0))

        // Collect events with a generous timeout. We expect at most one batch
        // of events (merged request), though each provider may produce its own event.
        var events: [DataPipeline.PipelineEvent] = []
        let deadline = Date().addingTimeInterval(10)

        for await event in await pipeline.events {
            events.append(event)
            // After getting events for both providers (or timeout), stop.
            if events.count >= 2 { break }
            if Date() > deadline { break }
        }

        // We should have received at least one event (error or update).
        #expect(!events.isEmpty, "Expected events from coalesced requests")
        await pipeline.shutdown()
    }
}
