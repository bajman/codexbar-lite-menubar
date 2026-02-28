import Foundation

struct CodexLiteFetcher {
    func fetchUsage() async throws -> UsageSnapshot {
        let credentials = try CodexOAuthCredentialsStore.load()
        let response = try await CodexOAuthUsageFetcher.fetchUsage(
            accessToken: credentials.accessToken,
            accountId: credentials.accountId)
        return Self.mapUsage(response, credentials: credentials)
    }

    func fetchCredits() async throws -> CreditsSnapshot? {
        let credentials = try CodexOAuthCredentialsStore.load()
        let response = try await CodexOAuthUsageFetcher.fetchUsage(
            accessToken: credentials.accessToken,
            accountId: credentials.accountId)
        guard let credits = response.credits, let balance = credits.balance else {
            return nil
        }
        return CreditsSnapshot(remaining: balance, events: [], updatedAt: Date())
    }

    private static func mapUsage(_ response: CodexUsageResponse, credentials: CodexOAuthCredentials) -> UsageSnapshot {
        let primary = Self.makeWindow(response.rateLimit?.primaryWindow)
        let secondary = Self.makeWindow(response.rateLimit?.secondaryWindow)

        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: Self.resolveAccountEmail(from: credentials),
            accountOrganization: nil,
            loginMethod: Self.resolvePlan(response: response, credentials: credentials))

        return UsageSnapshot(
            primary: primary ?? RateWindow(usedPercent: 0, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: secondary,
            tertiary: nil,
            updatedAt: Date(),
            identity: identity)
    }

    private static func makeWindow(_ window: CodexUsageResponse.WindowSnapshot?) -> RateWindow? {
        guard let window else { return nil }
        let resetDate = Date(timeIntervalSince1970: TimeInterval(window.resetAt))
        let resetDescription = UsageFormatter.resetDescription(from: resetDate)
        return RateWindow(
            usedPercent: Double(window.usedPercent),
            windowMinutes: window.limitWindowSeconds / 60,
            resetsAt: resetDate,
            resetDescription: resetDescription)
    }

    private static func resolveAccountEmail(from credentials: CodexOAuthCredentials) -> String? {
        guard let idToken = credentials.idToken,
              let payload = UsageFetcher.parseJWT(idToken)
        else {
            return nil
        }

        let profileDict = payload["https://api.openai.com/profile"] as? [String: Any]
        let email = (payload["email"] as? String) ?? (profileDict?["email"] as? String)
        return email?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolvePlan(response: CodexUsageResponse, credentials: CodexOAuthCredentials) -> String? {
        if let plan = response.planType?.rawValue, !plan.isEmpty { return plan }
        guard let idToken = credentials.idToken,
              let payload = UsageFetcher.parseJWT(idToken)
        else {
            return nil
        }
        let authDict = payload["https://api.openai.com/auth"] as? [String: Any]
        let plan = (authDict?["chatgpt_plan_type"] as? String) ?? (payload["chatgpt_plan_type"] as? String)
        return plan?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
