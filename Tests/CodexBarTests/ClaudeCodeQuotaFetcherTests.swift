import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ClaudeCodeQuotaFetcherTests {
    private actor AsyncCounter {
        private var value = 0

        func increment() -> Int {
            self.value += 1
            return self.value
        }

        func current() -> Int {
            self.value
        }
    }

    private static func makeResponse(statusCode: Int, headers: [String: String]) throws -> HTTPURLResponse {
        guard let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers)
        else {
            throw ClaudeOAuthFetchError.invalidResponse
        }
        return response
    }

    @Test
    func parsesUnifiedQuotaHeaders() throws {
        let response = try ClaudeCodeQuotaFetcher._decodeUsageResponseForTesting(headers: [
            "anthropic-ratelimit-unified-5h-utilization": "0.27",
            "anthropic-ratelimit-unified-5h-reset": "1_772_780_400".replacingOccurrences(of: "_", with: ""),
            "anthropic-ratelimit-unified-7d-utilization": "0.91",
            "anthropic-ratelimit-unified-7d-reset": "1772769600",
            "anthropic-ratelimit-unified-7d_sonnet-utilization": "0.46",
            "anthropic-ratelimit-unified-7d_sonnet-reset": "1772769600",
        ])

        #expect(response.fiveHour?.utilization == 0.27)
        #expect(response.sevenDay?.utilization == 0.91)
        #expect(response.sevenDaySonnet?.utilization == 0.46)
        #expect(response.fiveHour?.resetsAt == "2026-03-05T01:00:00Z")
        #expect(response.sevenDay?.resetsAt == "2026-03-04T22:00:00Z")
    }

    @Test
    func reusesRecentSuccessForBackgroundPolling() async throws {
        await ClaudeCodeQuotaFetcher._resetCacheForTesting()
        defer {
            Task {
                await ClaudeCodeQuotaFetcher._resetCacheForTesting()
            }
        }

        let counter = AsyncCounter()
        let now = Date(timeIntervalSince1970: 1000)
        let response = try Self.makeResponse(statusCode: 200, headers: [
            "anthropic-ratelimit-unified-5h-utilization": "0.18",
            "anthropic-ratelimit-unified-5h-reset": "1772780400",
            "anthropic-ratelimit-unified-7d-utilization": "0.44",
            "anthropic-ratelimit-unified-7d-reset": "1772769600",
        ])

        let performRequest: ClaudeCodeQuotaFetcher.PerformRequestOverride = { _ in
            _ = await counter.increment()
            return (Data(), response)
        }

        let first = try await ProviderInteractionContext.$current.withValue(.background) {
            try await ClaudeCodeQuotaFetcher.$nowOverride.withValue(now) {
                try await ClaudeCodeQuotaFetcher.$performRequestOverride.withValue(performRequest) {
                    try await ClaudeCodeQuotaFetcher.fetchUsage(accessToken: "token")
                }
            }
        }
        let second = try await ProviderInteractionContext.$current.withValue(.background) {
            try await ClaudeCodeQuotaFetcher.$nowOverride.withValue(now.addingTimeInterval(45)) {
                try await ClaudeCodeQuotaFetcher.$performRequestOverride.withValue(performRequest) {
                    try await ClaudeCodeQuotaFetcher.fetchUsage(accessToken: "token")
                }
            }
        }

        #expect(first.fiveHour?.utilization == 0.18)
        #expect(second.sevenDay?.utilization == 0.44)
        #expect(await counter.current() == 1)
    }

    @Test
    func rateLimitBackoffKeepsLastGoodSnapshotVisible() async throws {
        await ClaudeCodeQuotaFetcher._resetCacheForTesting()
        defer {
            Task {
                await ClaudeCodeQuotaFetcher._resetCacheForTesting()
            }
        }

        let counter = AsyncCounter()
        let start = Date(timeIntervalSince1970: 1000)
        let successResponse = try Self.makeResponse(statusCode: 200, headers: [
            "anthropic-ratelimit-unified-5h-utilization": "0.11",
            "anthropic-ratelimit-unified-5h-reset": "1772780400",
            "anthropic-ratelimit-unified-7d-utilization": "0.52",
            "anthropic-ratelimit-unified-7d-reset": "1772769600",
        ])
        let rateLimitedResponse = try Self.makeResponse(statusCode: 429, headers: [
            "Retry-After": "900",
        ])

        let performRequest: ClaudeCodeQuotaFetcher.PerformRequestOverride = { _ in
            let attempt = await counter.increment()
            if attempt == 1 {
                return (Data(), successResponse)
            }
            return (Data("{\"error\":\"rate_limited\"}".utf8), rateLimitedResponse)
        }

        let first = try await ProviderInteractionContext.$current.withValue(.background) {
            try await ClaudeCodeQuotaFetcher.$nowOverride.withValue(start) {
                try await ClaudeCodeQuotaFetcher.$performRequestOverride.withValue(performRequest) {
                    try await ClaudeCodeQuotaFetcher.fetchUsage(accessToken: "token")
                }
            }
        }
        let second = try await ProviderInteractionContext.$current.withValue(.background) {
            try await ClaudeCodeQuotaFetcher.$nowOverride.withValue(start.addingTimeInterval(601)) {
                try await ClaudeCodeQuotaFetcher.$performRequestOverride.withValue(performRequest) {
                    try await ClaudeCodeQuotaFetcher.fetchUsage(accessToken: "token")
                }
            }
        }
        let third = try await ProviderInteractionContext.$current.withValue(.background) {
            try await ClaudeCodeQuotaFetcher.$nowOverride.withValue(start.addingTimeInterval(700)) {
                try await ClaudeCodeQuotaFetcher.$performRequestOverride.withValue(performRequest) {
                    try await ClaudeCodeQuotaFetcher.fetchUsage(accessToken: "token")
                }
            }
        }

        #expect(first.sevenDay?.utilization == 0.52)
        #expect(second.fiveHour?.utilization == 0.11)
        #expect(third.sevenDay?.utilization == 0.52)
        #expect(await counter.current() == 2)
    }
}
