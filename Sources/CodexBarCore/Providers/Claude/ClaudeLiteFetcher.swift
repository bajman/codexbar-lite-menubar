import Foundation

private enum ClaudeLiteFetcherError: LocalizedError {
    case missingCredentials
    case invalidCredentials

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Claude credentials not found. Run `claude login`."
        case .invalidCredentials:
            return "Claude credentials are invalid. Run `claude login`."
        }
    }
}

struct ClaudeLiteFetcher {
    private let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    func fetchUsage() async throws -> UsageSnapshot {
        let credentials = try self.loadCredentials()
        let response = try await ClaudeOAuthUsageFetcher.fetchUsage(accessToken: credentials.accessToken)
        return Self.mapUsage(response, credentials: credentials)
    }

    private func loadCredentials() throws -> ClaudeOAuthCredentials {
        var sawCandidatePayload = false

        // Lite policy: keychain first using prompt-free security CLI read.
        if let fromSecurityCLI = ClaudeOAuthCredentialsStore.loadFromClaudeKeychainViaSecurityCLIIfEnabled(
            interaction: ProviderInteractionContext.current,
            readStrategy: .securityCLIExperimental)
        {
            sawCandidatePayload = true
            if let parsed = try? ClaudeOAuthCredentials.parse(data: fromSecurityCLI),
               !parsed.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return parsed
            }
        }

        // Fallback to the existing OAuth credential resolver (cache + file + prompt-gated keychain logic).
        if let record = try? ClaudeOAuthCredentialsStore.loadRecord(
            environment: self.environment,
            allowKeychainPrompt: false,
            respectKeychainPromptCooldown: true,
            allowClaudeKeychainRepairWithoutPrompt: true)
        {
            let parsed = record.credentials
            sawCandidatePayload = true
            if !parsed.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return parsed
            }
        }

        // File fallback for CLI variants that persist credentials in ~/.claude.
        for fileURL in Self.credentialFileCandidates(environment: self.environment) {
            guard let fileData = try? Data(contentsOf: fileURL) else { continue }
            sawCandidatePayload = true
            if let parsed = try? ClaudeOAuthCredentials.parse(data: fileData),
               !parsed.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return parsed
            }
        }

        if sawCandidatePayload {
            throw ClaudeLiteFetcherError.invalidCredentials
        }
        throw ClaudeLiteFetcherError.missingCredentials
    }

    private static func credentialFileCandidates(environment: [String: String]) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let basePath = environment["CLAUDE_CONFIG_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = URL(fileURLWithPath: (basePath?.isEmpty == false ? basePath! : "\(home.path)/.claude"))
        return [
            root.appendingPathComponent(".credentials.json"),
            root.appendingPathComponent("credentials.json"),
        ]
    }

    private static func mapUsage(_ response: OAuthUsageResponse, credentials: ClaudeOAuthCredentials) -> UsageSnapshot {
        let primary = Self.makeWindow(response.fiveHour)
            ?? RateWindow(usedPercent: 0, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let secondary = Self.makeWindow(response.sevenDay)
        let tertiary = Self.makeWindow(response.sevenDayOpus ?? response.sevenDaySonnet)

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

    private static func makeWindow(_ window: OAuthUsageWindow?) -> RateWindow? {
        guard let window else { return nil }
        let usedPercent = Self.normalizeUsedPercent(window.utilization)
        let resetDate = ClaudeOAuthUsageFetcher.parseISO8601Date(window.resetsAt)
        let resetDescription = resetDate.map { UsageFormatter.resetDescription(from: $0) }
        return RateWindow(
            usedPercent: usedPercent,
            windowMinutes: nil,
            resetsAt: resetDate,
            resetDescription: resetDescription)
    }

    private static func normalizeUsedPercent(_ utilization: Double?) -> Double {
        guard let utilization else { return 0 }
        // Anthropic has returned both ratio (0...1) and percent (0...100) formats.
        let value = utilization <= 1 ? utilization * 100 : utilization
        return max(0, min(100, value))
    }
}
