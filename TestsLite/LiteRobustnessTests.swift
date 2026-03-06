import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@Suite(.serialized)
struct LiteRobustnessTests {
    private static func makeOAuthUsageResponse() throws -> OAuthUsageResponse {
        let json = """
        {
          "five_hour": { "utilization": 7, "resets_at": "2025-12-23T16:00:00.000Z" },
          "seven_day": { "utilization": 21, "resets_at": "2025-12-29T23:00:00.000Z" }
        }
        """
        return try ClaudeOAuthUsageFetcher._decodeUsageResponseForTesting(Data(json.utf8))
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
        let now = Date(timeIntervalSince1970: 1_000)
        var state = StatusRefreshState()

        #expect(state.shouldRefresh(now: now, ttl: 600, force: false) == true)

        state.recordSuccess(now: now)
        #expect(state.shouldRefresh(now: now.addingTimeInterval(120), ttl: 600, force: false) == false)
        #expect(state.shouldRefresh(now: now.addingTimeInterval(601), ttl: 600, force: false) == true)

        state.recordFailure(now: now.addingTimeInterval(601), baseBackoff: 60, maxBackoff: 1_800)
        #expect(state.shouldRefresh(now: now.addingTimeInterval(620), ttl: 600, force: false) == false)
        #expect(state.shouldRefresh(now: now.addingTimeInterval(662), ttl: 600, force: false) == true)

        state.recordFailure(now: now.addingTimeInterval(662), baseBackoff: 60, maxBackoff: 1_800)
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

    @Test
    func localClaudeLogsDriveEstimatedFiveHourWindow() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let currentBlockStart = now.addingTimeInterval(-2 * 3_600)
        let olderBlockStart = now.addingTimeInterval(-12 * 3_600)

        let report = CostUsageScanner.ClaudeRecentUsageReport(
            entries: [
                .init(
                    timestamp: olderBlockStart,
                    model: "claude-sonnet-4-5",
                    inputTokens: 30_000,
                    cacheReadTokens: 0,
                    cacheCreationTokens: 0,
                    outputTokens: 6_000),
                .init(
                    timestamp: olderBlockStart.addingTimeInterval(600),
                    model: "claude-sonnet-4-5",
                    inputTokens: 18_000,
                    cacheReadTokens: 0,
                    cacheCreationTokens: 0,
                    outputTokens: 6_000),
                .init(
                    timestamp: currentBlockStart,
                    model: "claude-sonnet-4-5",
                    inputTokens: 24_000,
                    cacheReadTokens: 0,
                    cacheCreationTokens: 0,
                    outputTokens: 6_000),
                .init(
                    timestamp: currentBlockStart.addingTimeInterval(900),
                    model: "claude-sonnet-4-5",
                    inputTokens: 18_000,
                    cacheReadTokens: 0,
                    cacheCreationTokens: 0,
                    outputTokens: 6_000),
            ],
            foundAnyLogs: true)

        let fetcher = ClaudeLocalUsageFetcher(environment: [:], nowProvider: { now })
        let snapshot = try await ClaudeLocalUsageFetcher.$loadUsageReportOverride.withValue({ _, _ in report }) {
            try await ClaudeLocalUsageFetcher.$loadRateLimitTierOverride.withValue({ _ in "claude_pro" }) {
                try await fetcher.fetchUsage()
            }
        }

        #expect(snapshot.primary?.windowMinutes == 300)
        #expect(snapshot.primary?.resetsAt == currentBlockStart.addingTimeInterval(5 * 3_600))
        #expect(snapshot.primary?.usedPercent ?? 0 > 0)
        #expect(snapshot.primary?.usedPercent ?? 0 < 100)
        #expect(snapshot.secondary == nil)
        #expect(snapshot.identity?.loginMethod == "Claude Pro")
    }

    @Test
    func localClaudeFetcherThrowsWhenNoLogsExist() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fetcher = ClaudeLocalUsageFetcher(environment: [:], nowProvider: { now })

        await #expect(throws: ClaudeLocalUsageError.self) {
            try await ClaudeLocalUsageFetcher.$loadUsageReportOverride.withValue({ _, _ in
                CostUsageScanner.ClaudeRecentUsageReport(entries: [], foundAnyLogs: false)
            }) {
                try await fetcher.fetchUsage()
            }
        }
    }

    @Test
    func expiredCLIManagedCredentialsStillLoadWhenServerAcceptsToken() async throws {
        let usageResponse = try Self.makeOAuthUsageResponse()
        let expiredRecord = ClaudeOAuthCredentialRecord(
            credentials: ClaudeOAuthCredentials(
                accessToken: "expired-but-still-valid",
                refreshToken: "refresh-token",
                expiresAt: Date(timeIntervalSinceNow: -3_600),
                scopes: ["user:profile"],
                rateLimitTier: "default_claude_max_20x"),
            owner: .claudeCLI,
            source: .claudeKeychain)

        let fetcher = ClaudeLiteFetcher(environment: [:])
        let snapshot = try await ClaudeLiteFetcher.$loadRecordOverride.withValue({ _, _, _ in expiredRecord }) {
            try await ClaudeLiteFetcher.$fetchUsageOverride.withValue({ accessToken in
                #expect(accessToken == "expired-but-still-valid")
                return usageResponse
            }) {
                try await fetcher.fetchUsage()
            }
        }

        #expect(snapshot.primary?.usedPercent == 7)
        #expect(snapshot.secondary?.usedPercent == 21)
        #expect(snapshot.identity?.loginMethod == "default_claude_max_20x")
    }

    @Test
    func expiredCLIManagedCredentialsSurfaceDelegatedRefreshAfterUnauthorized() async throws {
        let expiredRecord = ClaudeOAuthCredentialRecord(
            credentials: ClaudeOAuthCredentials(
                accessToken: "expired-token",
                refreshToken: "refresh-token",
                expiresAt: Date(timeIntervalSinceNow: -3_600),
                scopes: ["user:profile"],
                rateLimitTier: nil),
            owner: .claudeCLI,
            source: .claudeKeychain)

        let fetcher = ClaudeLiteFetcher(environment: [:])

        do {
            try await ClaudeLiteFetcher.$loadRecordOverride.withValue({ _, _, _ in expiredRecord }) {
                try await ClaudeLiteFetcher.$fetchUsageOverride.withValue({ _ in
                    throw ClaudeOAuthFetchError.unauthorized
                }) {
                    try await ClaudeLiteFetcher.$syncFromClaudeKeychainOverride.withValue({ false }) {
                        _ = try await fetcher.fetchUsage()
                    }
                }
            }
            Issue.record("Expected delegated refresh error for unauthorized Claude CLI credentials")
        } catch let error as ClaudeOAuthCredentialsError {
            guard case .refreshDelegatedToClaudeCLI = error else {
                Issue.record("Expected .refreshDelegatedToClaudeCLI, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected ClaudeOAuthCredentialsError, got \(error)")
        }
    }

    @Test
    func unauthorizedEnvironmentCredentialsSurfaceNoRefreshToken() async throws {
        let environmentRecord = ClaudeOAuthCredentialRecord(
            credentials: ClaudeOAuthCredentials(
                accessToken: "environment-token",
                refreshToken: nil,
                expiresAt: Date(timeIntervalSinceNow: -3_600),
                scopes: ["user:profile"],
                rateLimitTier: nil),
            owner: .environment,
            source: .environment)

        let fetcher = ClaudeLiteFetcher(environment: [:])

        do {
            try await ClaudeLiteFetcher.$loadRecordOverride.withValue({ _, _, _ in environmentRecord }) {
                try await ClaudeLiteFetcher.$fetchUsageOverride.withValue({ _ in
                    throw ClaudeOAuthFetchError.unauthorized
                }) {
                    _ = try await fetcher.fetchUsage()
                }
            }
            Issue.record("Expected no-refresh-token error for environment credentials")
        } catch let error as ClaudeOAuthCredentialsError {
            guard case .noRefreshToken = error else {
                Issue.record("Expected .noRefreshToken, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected ClaudeOAuthCredentialsError, got \(error)")
        }
    }
}
