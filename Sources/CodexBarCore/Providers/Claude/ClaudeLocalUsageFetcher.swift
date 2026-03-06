import Foundation

enum ClaudeLocalUsageError: LocalizedError, Sendable {
    case noLogsFound

    var errorDescription: String? {
        switch self {
        case .noLogsFound:
            "No Claude usage logs were found locally."
        }
    }
}

struct ClaudeLocalUsageFetcher {
    private struct LocalSessionBlock: Sendable, Equatable {
        let start: Date
        let resetsAt: Date
        let messageCount: Int
        let totalTokens: Int

        var averageTokensPerMessage: Double {
            guard self.messageCount > 0 else { return 0 }
            return Double(self.totalTokens) / Double(self.messageCount)
        }
    }

    private struct QuotaHeuristic: Sendable, Equatable {
        let loginMethod: String?
        let nominalMessagesPerWindow: Int
        let baselineTokensPerMessage: Int
    }

    private let environment: [String: String]
    private let nowProvider: @Sendable () -> Date

    #if DEBUG
    typealias LoadUsageReportOverride = @Sendable (Date, Date) async throws -> CostUsageScanner.ClaudeRecentUsageReport
    typealias LoadRateLimitTierOverride = @Sendable ([String: String]) async throws -> String?

    @TaskLocal static var loadUsageReportOverride: LoadUsageReportOverride?
    @TaskLocal static var loadRateLimitTierOverride: LoadRateLimitTierOverride?
    #endif

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        nowProvider: @escaping @Sendable () -> Date = Date.init)
    {
        self.environment = environment
        self.nowProvider = nowProvider
    }

    func fetchUsage() async throws -> UsageSnapshot {
        let now = self.nowProvider()
        let scanSince = Calendar.current.date(byAdding: .hour, value: -24, to: now) ?? now
            .addingTimeInterval(-24 * 3600)
        let report = try await self.loadUsageReport(since: scanSince, until: now)
        guard report.foundAnyLogs else {
            throw ClaudeLocalUsageError.noLogsFound
        }

        let blocks = Self.makeBlocks(from: report.entries)
        let activeBlock = blocks.last.flatMap { block in
            now < block.resetsAt ? block : nil
        }
        let rateLimitTier = try await self.loadRateLimitTier()
        let heuristic = Self.quotaHeuristic(for: rateLimitTier)
        let primary = Self.makePrimaryWindow(
            activeBlock: activeBlock,
            blocks: blocks,
            now: now,
            heuristic: heuristic)
        let identity = ProviderIdentitySnapshot(
            providerID: .claude,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: heuristic.loginMethod)

        return UsageSnapshot(
            primary: primary,
            secondary: nil,
            tertiary: nil,
            providerCost: nil,
            updatedAt: report.entries.last?.timestamp ?? now,
            identity: identity)
    }

    func debugRawProbe() async -> String {
        do {
            let usage = try await self.fetchUsage()
            let session = usage.primary?.usedPercent ?? 0
            let reset = usage.primary?.resetsAt?.description ?? "nil"
            let plan = usage.identity?.loginMethod ?? "unknown"
            let updated = usage.updatedAt.description
            return "source=local session_used=\(Int(session.rounded())) "
                + "resetAt=\(reset) weekly=nil plan=\(plan) updatedAt=\(updated)"
        } catch {
            return "Local probe failed: \(error.localizedDescription)"
        }
    }

    private func loadUsageReport(since: Date, until: Date) async throws -> CostUsageScanner.ClaudeRecentUsageReport {
        #if DEBUG
        if let override = Self.loadUsageReportOverride {
            return try await override(since, until)
        }
        #endif

        var options = CostUsageScanner.Options()
        options.claudeLogProviderFilter = .excludeVertexAI
        return CostUsageScanner.loadClaudeRecentUsage(
            since: since,
            until: until,
            options: options)
    }

    private func loadRateLimitTier() async throws -> String? {
        #if DEBUG
        if let override = Self.loadRateLimitTierOverride {
            return try await override(self.environment)
        }
        #endif

        let record = try? ClaudeOAuthCredentialsStore.loadRecord(
            environment: self.environment,
            allowKeychainPrompt: false,
            respectKeychainPromptCooldown: true)
        return record?.credentials.rateLimitTier
    }

    private static func makeBlocks(from entries: [CostUsageScanner.ClaudeRecentUsageEntry]) -> [LocalSessionBlock] {
        guard !entries.isEmpty else { return [] }

        var blocks: [LocalSessionBlock] = []
        var currentStart = entries[0].timestamp
        var currentReset = currentStart.addingTimeInterval(5 * 3600)
        var currentMessages = 0
        var currentTokens = 0

        func flushCurrentBlock() {
            blocks.append(LocalSessionBlock(
                start: currentStart,
                resetsAt: currentReset,
                messageCount: currentMessages,
                totalTokens: currentTokens))
        }

        for entry in entries {
            if entry.timestamp >= currentReset {
                flushCurrentBlock()
                currentStart = entry.timestamp
                currentReset = currentStart.addingTimeInterval(5 * 3600)
                currentMessages = 0
                currentTokens = 0
            }
            currentMessages += 1
            currentTokens += entry.totalTokens
        }

        flushCurrentBlock()
        return blocks
    }

    private static func makePrimaryWindow(
        activeBlock: LocalSessionBlock?,
        blocks: [LocalSessionBlock],
        now: Date,
        heuristic: QuotaHeuristic) -> RateWindow
    {
        guard let activeBlock else {
            return RateWindow(
                usedPercent: 0,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil)
        }

        let recentAverages = blocks
            .suffix(12)
            .compactMap { block -> Double? in
                guard block.messageCount > 0 else { return nil }
                return block.averageTokensPerMessage
            }
        let baselineAverage = Double(heuristic.baselineTokensPerMessage)
        let historicalAverage = if recentAverages.isEmpty {
            baselineAverage
        } else {
            recentAverages.reduce(0, +) / Double(recentAverages.count)
        }
        let boundedAverage = min(max(historicalAverage, baselineAverage * 0.5), baselineAverage * 6)

        let historicalCap = blocks
            .filter { $0.resetsAt <= now }
            .map(\.totalTokens)
            .max() ?? 0
        let nominalTokenCap = Int((Double(heuristic.nominalMessagesPerWindow) * boundedAverage).rounded())
        let tokenCapacity = max(nominalTokenCap, historicalCap, activeBlock.totalTokens, 1)

        let messagePercent = (Double(activeBlock.messageCount) / Double(max(heuristic.nominalMessagesPerWindow, 1))) *
            100
        let tokenPercent = (Double(activeBlock.totalTokens) / Double(tokenCapacity)) * 100
        let usedPercent = min(100, max(messagePercent, tokenPercent))
        return RateWindow(
            usedPercent: usedPercent,
            windowMinutes: 300,
            resetsAt: activeBlock.resetsAt,
            resetDescription: UsageFormatter.resetDescription(from: activeBlock.resetsAt))
    }

    private static func quotaHeuristic(for rateLimitTier: String?) -> QuotaHeuristic {
        let cleanedTier = rateLimitTier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch cleanedTier {
        case let tier? where tier.contains("20x"):
            return QuotaHeuristic(
                loginMethod: "Claude Max 20x",
                nominalMessagesPerWindow: 900,
                baselineTokensPerMessage: 12000)
        case let tier? where tier.contains("5x"):
            return QuotaHeuristic(
                loginMethod: "Claude Max 5x",
                nominalMessagesPerWindow: 225,
                baselineTokensPerMessage: 12000)
        case let tier? where tier.contains("enterprise"):
            return QuotaHeuristic(
                loginMethod: "Claude Enterprise",
                nominalMessagesPerWindow: 450,
                baselineTokensPerMessage: 12000)
        case let tier? where tier.contains("team"):
            return QuotaHeuristic(
                loginMethod: "Claude Team",
                nominalMessagesPerWindow: 225,
                baselineTokensPerMessage: 12000)
        case let tier? where tier.contains("max"):
            return QuotaHeuristic(
                loginMethod: "Claude Max",
                nominalMessagesPerWindow: 225,
                baselineTokensPerMessage: 12000)
        case let tier? where tier.contains("pro"):
            return QuotaHeuristic(
                loginMethod: "Claude Pro",
                nominalMessagesPerWindow: 45,
                baselineTokensPerMessage: 12000)
        case let tier? where !tier.isEmpty:
            return QuotaHeuristic(
                loginMethod: rateLimitTier,
                nominalMessagesPerWindow: 45,
                baselineTokensPerMessage: 12000)
        default:
            return QuotaHeuristic(
                loginMethod: nil,
                nominalMessagesPerWindow: 45,
                baselineTokensPerMessage: 12000)
        }
    }
}
