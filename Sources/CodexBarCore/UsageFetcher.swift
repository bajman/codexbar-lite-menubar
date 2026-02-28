import Foundation

public struct RateWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let windowMinutes: Int?
    public let resetsAt: Date?
    public let resetDescription: String?

    public init(usedPercent: Double, windowMinutes: Int?, resetsAt: Date?, resetDescription: String?) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
    }

    public var remainingPercent: Double {
        max(0, 100 - self.usedPercent)
    }
}

public struct ProviderIdentitySnapshot: Codable, Sendable {
    public let providerID: UsageProvider?
    public let accountEmail: String?
    public let accountOrganization: String?
    public let loginMethod: String?

    public init(
        providerID: UsageProvider?,
        accountEmail: String?,
        accountOrganization: String?,
        loginMethod: String?)
    {
        self.providerID = providerID
        self.accountEmail = accountEmail
        self.accountOrganization = accountOrganization
        self.loginMethod = loginMethod
    }

    public func scoped(to provider: UsageProvider) -> ProviderIdentitySnapshot {
        if self.providerID == provider { return self }
        return ProviderIdentitySnapshot(
            providerID: provider,
            accountEmail: self.accountEmail,
            accountOrganization: self.accountOrganization,
            loginMethod: self.loginMethod)
    }
}

public struct UsageSnapshot: Codable, Sendable {
    public let primary: RateWindow?
    public let secondary: RateWindow?
    public let tertiary: RateWindow?
    public let providerCost: ProviderCostSnapshot?
    public let updatedAt: Date
    public let identity: ProviderIdentitySnapshot?

    private enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case tertiary
        case providerCost
        case updatedAt
        case identity
        case accountEmail
        case accountOrganization
        case loginMethod
    }

    public init(
        primary: RateWindow?,
        secondary: RateWindow?,
        tertiary: RateWindow? = nil,
        providerCost: ProviderCostSnapshot? = nil,
        updatedAt: Date,
        identity: ProviderIdentitySnapshot? = nil)
    {
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
        self.providerCost = providerCost
        self.updatedAt = updatedAt
        self.identity = identity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.primary = try container.decodeIfPresent(RateWindow.self, forKey: .primary)
        self.secondary = try container.decodeIfPresent(RateWindow.self, forKey: .secondary)
        self.tertiary = try container.decodeIfPresent(RateWindow.self, forKey: .tertiary)
        self.providerCost = try container.decodeIfPresent(ProviderCostSnapshot.self, forKey: .providerCost)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        if let identity = try container.decodeIfPresent(ProviderIdentitySnapshot.self, forKey: .identity) {
            self.identity = identity
        } else {
            let email = try container.decodeIfPresent(String.self, forKey: .accountEmail)
            let organization = try container.decodeIfPresent(String.self, forKey: .accountOrganization)
            let loginMethod = try container.decodeIfPresent(String.self, forKey: .loginMethod)
            if email != nil || organization != nil || loginMethod != nil {
                self.identity = ProviderIdentitySnapshot(
                    providerID: nil,
                    accountEmail: email,
                    accountOrganization: organization,
                    loginMethod: loginMethod)
            } else {
                self.identity = nil
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.primary, forKey: .primary)
        try container.encode(self.secondary, forKey: .secondary)
        try container.encode(self.tertiary, forKey: .tertiary)
        try container.encodeIfPresent(self.providerCost, forKey: .providerCost)
        try container.encode(self.updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(self.identity, forKey: .identity)
        try container.encodeIfPresent(self.identity?.accountEmail, forKey: .accountEmail)
        try container.encodeIfPresent(self.identity?.accountOrganization, forKey: .accountOrganization)
        try container.encodeIfPresent(self.identity?.loginMethod, forKey: .loginMethod)
    }

    public func identity(for provider: UsageProvider) -> ProviderIdentitySnapshot? {
        guard let identity, identity.providerID == provider else { return nil }
        return identity
    }

    public func switcherWeeklyWindow(for _: UsageProvider, showUsed _: Bool) -> RateWindow? {
        self.primary ?? self.secondary
    }

    public func accountEmail(for provider: UsageProvider) -> String? {
        self.identity(for: provider)?.accountEmail
    }

    public func accountOrganization(for provider: UsageProvider) -> String? {
        self.identity(for: provider)?.accountOrganization
    }

    public func loginMethod(for provider: UsageProvider) -> String? {
        self.identity(for: provider)?.loginMethod
    }

    public func withIdentity(_ identity: ProviderIdentitySnapshot?) -> UsageSnapshot {
        UsageSnapshot(
            primary: self.primary,
            secondary: self.secondary,
            tertiary: self.tertiary,
            providerCost: self.providerCost,
            updatedAt: self.updatedAt,
            identity: identity)
    }

    public func scoped(to provider: UsageProvider) -> UsageSnapshot {
        guard let identity else { return self }
        let scopedIdentity = identity.scoped(to: provider)
        if scopedIdentity.providerID == identity.providerID { return self }
        return self.withIdentity(scopedIdentity)
    }
}

public struct AccountInfo: Equatable, Sendable {
    public let email: String?
    public let plan: String?

    public init(email: String?, plan: String?) {
        self.email = email
        self.plan = plan
    }
}

public enum UsageError: LocalizedError, Sendable {
    case noSessions
    case noRateLimitsFound
    case decodeFailed

    public var errorDescription: String? {
        switch self {
        case .noSessions:
            "No Codex sessions found yet. Run at least one Codex prompt first."
        case .noRateLimitsFound:
            "No Codex usage limits were returned by the OAuth endpoint."
        case .decodeFailed:
            "Could not parse Codex usage data."
        }
    }
}

public struct UsageFetcher: Sendable {
    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func loadLatestUsage(keepCLISessionsAlive _: Bool = false) async throws -> UsageSnapshot {
        let credentials = try CodexOAuthCredentialsStore.load()
        let response = try await CodexOAuthUsageFetcher.fetchUsage(
            accessToken: credentials.accessToken,
            accountId: credentials.accountId)
        return Self.mapUsage(response: response, credentials: credentials)
    }

    public func loadLatestCredits(keepCLISessionsAlive _: Bool = false) async throws -> CreditsSnapshot {
        let credentials = try CodexOAuthCredentialsStore.load()
        let response = try await CodexOAuthUsageFetcher.fetchUsage(
            accessToken: credentials.accessToken,
            accountId: credentials.accountId)
        guard let credits = response.credits, let balance = credits.balance else {
            throw UsageError.noRateLimitsFound
        }
        return CreditsSnapshot(remaining: balance, events: [], updatedAt: Date())
    }

    public func debugRawRateLimits() async -> String {
        do {
            let credentials = try CodexOAuthCredentialsStore.load()
            let response = try await CodexOAuthUsageFetcher.fetchUsage(
                accessToken: credentials.accessToken,
                accountId: credentials.accountId)
            return String(describing: response)
        } catch {
            return "Codex OAuth usage fetch failed: \(error)"
        }
    }

    public func loadAccountInfo() -> AccountInfo {
        let authURL = URL(fileURLWithPath: self.environment["CODEX_HOME"] ?? "\(NSHomeDirectory())/.codex")
            .appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: authURL),
              let auth = try? JSONDecoder().decode(AuthFile.self, from: data),
              let idToken = auth.tokens?.idToken
        else {
            return AccountInfo(email: nil, plan: nil)
        }

        guard let payload = UsageFetcher.parseJWT(idToken) else {
            return AccountInfo(email: nil, plan: nil)
        }

        let authDict = payload["https://api.openai.com/auth"] as? [String: Any]
        let profileDict = payload["https://api.openai.com/profile"] as? [String: Any]

        let plan = (authDict?["chatgpt_plan_type"] as? String)
            ?? (payload["chatgpt_plan_type"] as? String)

        let email = (payload["email"] as? String)
            ?? (profileDict?["email"] as? String)

        return AccountInfo(email: email, plan: plan)
    }

    public static func parseJWT(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let payloadPart = parts[1]

        var padded = String(payloadPart)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 {
            padded.append("=")
        }
        guard let data = Data(base64Encoded: padded) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json
    }

    private static func mapUsage(response: CodexUsageResponse, credentials: CodexOAuthCredentials) -> UsageSnapshot {
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

private struct AuthFile: Decodable {
    struct Tokens: Decodable { let idToken: String? }
    let tokens: Tokens?
}
