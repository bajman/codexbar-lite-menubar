import Foundation

public protocol ClaudeUsageFetching: Sendable {
    func loadLatestUsage(model: String) async throws -> ClaudeUsageSnapshot
    func debugRawProbe(model: String) async -> String
    func detectVersion() -> String?
}

public struct ClaudeUsageSnapshot: Sendable {
    public let primary: RateWindow
    public let secondary: RateWindow?
    public let opus: RateWindow?
    public let providerCost: ProviderCostSnapshot?
    public let updatedAt: Date
    public let accountEmail: String?
    public let accountOrganization: String?
    public let loginMethod: String?
    public let rawText: String?

    public init(
        primary: RateWindow,
        secondary: RateWindow?,
        opus: RateWindow?,
        providerCost: ProviderCostSnapshot? = nil,
        updatedAt: Date,
        accountEmail: String?,
        accountOrganization: String?,
        loginMethod: String?,
        rawText: String?)
    {
        self.primary = primary
        self.secondary = secondary
        self.opus = opus
        self.providerCost = providerCost
        self.updatedAt = updatedAt
        self.accountEmail = accountEmail
        self.accountOrganization = accountOrganization
        self.loginMethod = loginMethod
        self.rawText = rawText
    }
}

public enum ClaudeUsageError: LocalizedError, Sendable {
    case claudeNotInstalled
    case parseFailed(String)
    case oauthFailed(String)

    public var errorDescription: String? {
        switch self {
        case .claudeNotInstalled:
            "Claude CLI is not installed. Install it from https://code.claude.com/docs/en/overview."
        case let .parseFailed(details):
            "Could not parse Claude usage: \(details)"
        case let .oauthFailed(details):
            details
        }
    }
}

public struct ClaudeUsageFetcher: ClaudeUsageFetching, Sendable {
    private let environment: [String: String]
    private let browserDetection: BrowserDetection

    public init(
        browserDetection: BrowserDetection,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        dataSource _: ClaudeUsageDataSource = .oauth,
        oauthKeychainPromptCooldownEnabled _: Bool = false,
        allowBackgroundDelegatedRefresh _: Bool = false,
        allowStartupBootstrapPrompt _: Bool = false,
        useWebExtras _: Bool = false,
        manualCookieHeader _: String? = nil,
        keepCLISessionsAlive _: Bool = false)
    {
        self.browserDetection = browserDetection
        self.environment = environment
    }

    public func loadLatestUsage(model _: String = "sonnet") async throws -> ClaudeUsageSnapshot {
        let snapshot = try await ClaudeLiteFetcher(environment: self.environment).fetchUsage()
        guard let primary = snapshot.primary else {
            throw ClaudeUsageError.parseFailed("missing primary rate window")
        }
        return ClaudeUsageSnapshot(
            primary: primary,
            secondary: snapshot.secondary,
            opus: snapshot.tertiary,
            providerCost: snapshot.providerCost,
            updatedAt: snapshot.updatedAt,
            accountEmail: snapshot.identity?.accountEmail,
            accountOrganization: snapshot.identity?.accountOrganization,
            loginMethod: snapshot.identity?.loginMethod,
            rawText: nil)
    }

    public func debugRawProbe(model _: String = "sonnet") async -> String {
        do {
            let usage = try await self.loadLatestUsage(model: "sonnet")
            return "session_left=\(usage.primary.remainingPercent) weekly_left=\(usage.secondary?.remainingPercent ?? -1)"
        } catch {
            return "Probe failed: \(error)"
        }
    }

    public func detectVersion() -> String? {
        _ = self.browserDetection
        return ProviderVersionDetector.claudeVersion()
    }
}
