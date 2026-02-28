import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum ClaudeProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .claude,
            metadata: ProviderMetadata(
                id: .claude,
                displayName: "Claude",
                sessionLabel: "Session",
                weeklyLabel: "Weekly",
                opusLabel: "Sonnet",
                supportsOpus: true,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Claude Code usage",
                cliName: "claude",
                defaultEnabled: false,
                isPrimaryProvider: true,
                usesAccountFallback: false,
                browserCookieOrder: nil,
                dashboardURL: "https://console.anthropic.com/settings/billing",
                subscriptionDashboardURL: "https://claude.ai/settings/usage",
                statusPageURL: "https://status.claude.com/"),
            branding: ProviderBranding(
                iconStyle: .claude,
                iconResourceName: "ProviderIcon-claude",
                color: ProviderColor(red: 204 / 255, green: 124 / 255, blue: 94 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: true,
                noDataMessage: self.noDataMessage),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .oauth],
                pipeline: ProviderFetchPipeline(resolveStrategies: self.resolveStrategies)),
            cli: ProviderCLIConfig(
                name: "claude",
                versionDetector: { _ in ProviderVersionDetector.claudeVersion() }))
    }

    private static func resolveStrategies(context _: ProviderFetchContext) async -> [any ProviderFetchStrategy] {
        let strategies: [any ProviderFetchStrategy] = [ClaudeLiteFetchStrategy()]
        LitePolicy.validateStrategies(strategies, provider: .claude)
        return strategies
    }

    private static func noDataMessage() -> String {
        "No Claude usage logs found in ~/.claude."
    }

    public static func resolveUsageStrategy(
        selectedDataSource _: ClaudeUsageDataSource,
        webExtrasEnabled _: Bool,
        hasWebSession _: Bool,
        hasCLI _: Bool,
        hasOAuthCredentials _: Bool) -> ClaudeUsageStrategy
    {
        ClaudeUsageStrategy(dataSource: .oauth, useWebExtras: false)
    }
}

public struct ClaudeUsageStrategy: Equatable, Sendable {
    public let dataSource: ClaudeUsageDataSource
    public let useWebExtras: Bool
}

struct ClaudeLiteFetchStrategy: ProviderFetchStrategy {
    let id: String = "claude.oauth.lite"
    let kind: ProviderFetchKind = .oauth

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        true
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let fetcher = ClaudeLiteFetcher(environment: context.env)
        let usage = try await fetcher.fetchUsage()
        return self.makeResult(
            usage: usage,
            sourceLabel: "oauth")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
