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
                dashboardURL: "https://console.anthropic.com/settings/usage",
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

    private static func resolveStrategies(context: ProviderFetchContext) async -> [any ProviderFetchStrategy] {
        let strategies: [any ProviderFetchStrategy] = switch context.sourceMode {
        case .oauth:
            [ClaudeLiteFetchStrategy()]
        default:
            [ClaudeLiteFetchStrategy(), ClaudeLocalFetchStrategy()]
        }
        LitePolicy.validateStrategies(strategies, provider: .claude)
        return strategies
    }

    private static func noDataMessage() -> String {
        "No Claude usage logs found in ~/.claude."
    }

    public static func resolveUsageStrategy(
        selectedDataSource: ClaudeUsageDataSource,
        webExtrasEnabled _: Bool,
        hasWebSession _: Bool,
        hasCLI _: Bool,
        hasOAuthCredentials _: Bool) -> ClaudeUsageStrategy
    {
        switch selectedDataSource {
        case .oauth:
            ClaudeUsageStrategy(dataSource: .oauth, useWebExtras: false)
        case .auto, .cli, .web:
            ClaudeUsageStrategy(dataSource: .auto, useWebExtras: false)
        }
    }
}

public struct ClaudeUsageStrategy: Equatable, Sendable {
    public let dataSource: ClaudeUsageDataSource
    public let useWebExtras: Bool
}

struct ClaudeLiteFetchStrategy: ProviderFetchStrategy {
    let id: String = "claude.code.quota"
    let kind: ProviderFetchKind = .oauth

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        true
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let fetcher = ClaudeLiteFetcher(environment: context.env)
        let usage = try await fetcher.fetchUsage()
        return self.makeResult(
            usage: usage,
            sourceLabel: ClaudeUsageSourceLabels.live)
    }

    func shouldFallback(on error: Error, context: ProviderFetchContext) -> Bool {
        guard context.sourceMode == .auto else { return false }
        return ClaudeLiteFetcher.shouldFallbackToLocalLogs(on: error)
    }
}

struct ClaudeLocalFetchStrategy: ProviderFetchStrategy {
    let id: String = "claude.local.logs"
    let kind: ProviderFetchKind = .localProbe

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        true
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let usage = try await ClaudeLocalUsageFetcher(environment: context.env).fetchUsage()
        return self.makeResult(
            usage: usage,
            sourceLabel: ClaudeUsageSourceLabels.local)
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
