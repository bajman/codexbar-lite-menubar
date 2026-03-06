import Foundation

enum ClaudeLiteFetcherError: LocalizedError {
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Claude session not found. Open Terminal and run `claude` to authenticate."
        }
    }
}

struct ClaudeLiteFetcher {
    private let environment: [String: String]
    private static let clientVersion = ProviderVersionDetector.claudeVersion()

    #if DEBUG
    typealias LoadRecordOverride = @Sendable (
        [String: String],
        Bool,
        Bool) async throws -> ClaudeOAuthCredentialRecord
    typealias FetchUsageOverride = @Sendable (String) async throws -> OAuthUsageResponse
    typealias SyncFromClaudeKeychainOverride = @Sendable () -> Bool

    @TaskLocal static var loadRecordOverride: LoadRecordOverride?
    @TaskLocal static var fetchUsageOverride: FetchUsageOverride?
    @TaskLocal static var syncFromClaudeKeychainOverride: SyncFromClaudeKeychainOverride?
    #endif

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    static func shouldFallbackToLocalLogs(on error: Error) -> Bool {
        if let error = error as? ClaudeLiteFetcherError {
            switch error {
            case .missingCredentials:
                return true
            }
        }
        if let error = error as? ClaudeOAuthCredentialsError {
            switch error {
            case .notFound, .noRefreshToken, .refreshDelegatedToClaudeCLI:
                return true
            default:
                return false
            }
        }
        return false
    }

    func fetchUsage() async throws -> UsageSnapshot {
        let record = try await self.loadCredentialRecord()
        let (response, credentials) = try await self.fetchUsageResponse(using: record)
        return Self.mapUsage(response, credentials: credentials)
    }

    private func loadCredentialRecord() async throws -> ClaudeOAuthCredentialRecord {
        #if DEBUG
        if let override = Self.loadRecordOverride {
            return try await override(self.environment, false, true)
        }
        #endif

        do {
            return try ClaudeOAuthCredentialsStore.loadRecord(
                environment: self.environment,
                allowKeychainPrompt: false,
                respectKeychainPromptCooldown: true)
        } catch let error as ClaudeOAuthCredentialsError {
            if case .notFound = error {
                throw ClaudeLiteFetcherError.missingCredentials
            }
            throw error
        }
    }

    private func fetchUsageResponse(
        using record: ClaudeOAuthCredentialRecord) async throws -> (OAuthUsageResponse, ClaudeOAuthCredentials)
    {
        let initialCredentials = record.credentials

        do {
            let response = try await Self.fetchOAuthUsage(accessToken: initialCredentials.accessToken)
            return (response, initialCredentials)
        } catch let error as ClaudeOAuthFetchError {
            guard case .unauthorized = error else { throw error }
            let recoveredCredentials = try await self.recoverUnauthorizedCredentials(from: record)
            let response = try await Self.fetchOAuthUsage(accessToken: recoveredCredentials.accessToken)
            return (response, recoveredCredentials)
        }
    }

    private func recoverUnauthorizedCredentials(
        from record: ClaudeOAuthCredentialRecord) async throws -> ClaudeOAuthCredentials
    {
        switch record.owner {
        case .codexbar:
            return try await ClaudeOAuthCredentialsStore.loadWithAutoRefresh(
                environment: self.environment,
                allowKeychainPrompt: false,
                respectKeychainPromptCooldown: true)
        case .environment:
            throw ClaudeOAuthCredentialsError.noRefreshToken
        case .claudeCLI:
            let syncedWithoutPrompt = {
                #if DEBUG
                if let override = Self.syncFromClaudeKeychainOverride {
                    return override()
                }
                #endif
                return ClaudeOAuthCredentialsStore.syncFromClaudeKeychainWithoutPrompt()
            }()
            if syncedWithoutPrompt,
               let synced = try? ClaudeOAuthCredentialsStore.loadRecord(
                   environment: self.environment,
                   allowKeychainPrompt: false,
                   respectKeychainPromptCooldown: true)
            {
                let accessToken = synced.credentials.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
                if !accessToken.isEmpty {
                    return synced.credentials
                }
            }
            throw ClaudeOAuthCredentialsError.refreshDelegatedToClaudeCLI
        }
    }

    private static func fetchOAuthUsage(accessToken: String) async throws -> OAuthUsageResponse {
        #if DEBUG
        if let override = fetchUsageOverride {
            return try await override(accessToken)
        }
        #endif
        return try await ClaudeCodeQuotaFetcher.fetchUsage(
            accessToken: accessToken,
            clientVersion: self.clientVersion)
    }

    private static func mapUsage(_ response: OAuthUsageResponse, credentials: ClaudeOAuthCredentials) -> UsageSnapshot {
        let utilizationScale = Self.utilizationScale(for: response)
        let primary = Self.makeWindow(response.fiveHour, utilizationScale: utilizationScale)
            ?? RateWindow(usedPercent: 0, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let secondary = Self.makeWindow(response.sevenDay, utilizationScale: utilizationScale)
        let tertiary = Self.makeWindow(
            response.sevenDayOpus ?? response.sevenDaySonnet,
            utilizationScale: utilizationScale)

        let providerCost: ProviderCostSnapshot? = {
            guard let extra = response.extraUsage,
                  extra.isEnabled == true,
                  let limit = extra.monthlyLimit,
                  let used = extra.usedCredits,
                  limit > 0
            else {
                return nil
            }
            // Anthropic OAuth usage reports monetary values in minor units (for USD, cents).
            let normalizedUsed = used / 100
            let normalizedLimit = limit / 100
            return ProviderCostSnapshot(
                used: normalizedUsed,
                limit: normalizedLimit,
                currencyCode: extra.currency ?? "USD",
                updatedAt: Date())
        }()

        let identity = ProviderIdentitySnapshot(
            providerID: .claude,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: credentials.rateLimitTier)

        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
            providerCost: providerCost,
            updatedAt: Date(),
            identity: identity)
    }

    private static func makeWindow(_ window: OAuthUsageWindow?, utilizationScale: UtilizationScale) -> RateWindow? {
        guard let window else { return nil }
        let usedPercent = Self.normalizeUsedPercent(window.utilization, utilizationScale: utilizationScale)
        let resetDate = ClaudeOAuthUsageFetcher.parseISO8601Date(window.resetsAt)
        let resetDescription = resetDate.map { UsageFormatter.resetDescription(from: $0) }
        return RateWindow(
            usedPercent: usedPercent,
            windowMinutes: nil,
            resetsAt: resetDate,
            resetDescription: resetDescription)
    }

    private enum UtilizationScale {
        case ratio
        case percent
    }

    private static func utilizationScale(for response: OAuthUsageResponse) -> UtilizationScale {
        let candidates: [Double?] = [
            response.fiveHour?.utilization,
            response.sevenDay?.utilization,
            response.sevenDayOAuthApps?.utilization,
            response.sevenDayOpus?.utilization,
            response.sevenDaySonnet?.utilization,
            response.iguanaNecktie?.utilization,
        ]
        let values = candidates.compactMap(\.self)
        return Self.detectUtilizationScale(values)
    }

    private static func detectUtilizationScale(_ values: [Double]) -> UtilizationScale {
        guard !values.isEmpty else { return .percent }

        if values.contains(where: { $0 > 1 }) { return .percent }

        let hasFractionalSubunit = values.contains { value in
            guard value > 0, value < 1 else { return false }
            return abs(value.rounded() - value) > 0.0001
        }
        if hasFractionalSubunit { return .ratio }

        if values.contains(where: { $0 > 0 && $0 < 0.01 }) { return .ratio }

        return .percent
    }

    private static func normalizeUsedPercent(_ utilization: Double?, utilizationScale: UtilizationScale) -> Double {
        guard let utilization else { return 0 }
        // Anthropic has returned both ratio (0...1) and percent (0...100) formats.
        let value = utilizationScale == .ratio ? utilization * 100 : utilization
        return max(0, min(100, value))
    }

    #if DEBUG
    static func _mapUsageForTesting(
        _ response: OAuthUsageResponse,
        credentials: ClaudeOAuthCredentials) -> UsageSnapshot
    {
        self.mapUsage(response, credentials: credentials)
    }
    #endif
}
