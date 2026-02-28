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
        // Lite policy: keychain first, then ~/.claude/.credentials.json fallback.
        if let fromKeychain = try? ClaudeOAuthCredentialsStore.loadFromClaudeKeychain(),
           let parsed = try? ClaudeOAuthCredentials.parse(data: fromKeychain),
           !parsed.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return parsed
        }

        if let fromFile = try? Self.loadCredentialsFromFile(environment: self.environment),
           let parsed = try? ClaudeOAuthCredentials.parse(data: fromFile),
           !parsed.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return parsed
        }

        if (try? Self.loadCredentialsFromFile(environment: self.environment)) != nil {
            throw ClaudeLiteFetcherError.invalidCredentials
        }
        throw ClaudeLiteFetcherError.missingCredentials
    }

    private static func loadCredentialsFromFile(environment: [String: String]) throws -> Data {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let base = environment["CLAUDE_CONFIG_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = (base?.isEmpty == false ? base! : "\(home.path)/.claude")
        let fileURL = URL(fileURLWithPath: path).appendingPathComponent(".credentials.json")
        return try Data(contentsOf: fileURL)
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
            return ProviderCostSnapshot(
                used: used,
                limit: limit,
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
        let utilization = window.utilization ?? 0
        let usedPercent = max(0, min(100, utilization * 100))
        let resetDate = ClaudeOAuthUsageFetcher.parseISO8601Date(window.resetsAt)
        let resetDescription = resetDate.map { UsageFormatter.resetDescription(from: $0) }
        return RateWindow(
            usedPercent: usedPercent,
            windowMinutes: nil,
            resetsAt: resetDate,
            resetDescription: resetDescription)
    }
}
