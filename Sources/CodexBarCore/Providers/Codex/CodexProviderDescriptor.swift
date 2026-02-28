import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum CodexProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .codex,
            metadata: ProviderMetadata(
                id: .codex,
                displayName: "Codex",
                sessionLabel: "Session",
                weeklyLabel: "Weekly",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: true,
                creditsHint: "Credits unavailable; run `codex login` if auth expired.",
                toggleTitle: "Show Codex usage",
                cliName: "codex",
                defaultEnabled: true,
                isPrimaryProvider: true,
                usesAccountFallback: false,
                browserCookieOrder: nil,
                dashboardURL: nil,
                statusPageURL: "https://status.openai.com/"),
            branding: ProviderBranding(
                iconStyle: .codex,
                iconResourceName: "ProviderIcon-codex",
                color: ProviderColor(red: 73 / 255, green: 163 / 255, blue: 176 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: true,
                noDataMessage: self.noDataMessage),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .oauth],
                pipeline: ProviderFetchPipeline(resolveStrategies: self.resolveStrategies)),
            cli: ProviderCLIConfig(
                name: "codex",
                versionDetector: { _ in ProviderVersionDetector.codexVersion() }))
    }

    private static func resolveStrategies(context _: ProviderFetchContext) async -> [any ProviderFetchStrategy] {
        let strategies: [any ProviderFetchStrategy] = [CodexLiteFetchStrategy()]
        LitePolicy.validateStrategies(strategies, provider: .codex)
        return strategies
    }

    private static func noDataMessage() -> String {
        "No Codex usage data available."
    }

    public static func resolveUsageStrategy(
        selectedDataSource _: CodexUsageDataSource,
        hasOAuthCredentials _: Bool) -> CodexUsageStrategy
    {
        CodexUsageStrategy(dataSource: .oauth)
    }
}

public struct CodexUsageStrategy: Equatable, Sendable {
    public let dataSource: CodexUsageDataSource
}

struct CodexLiteFetchStrategy: ProviderFetchStrategy {
    let id: String = "codex.oauth.lite"
    let kind: ProviderFetchKind = .oauth

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        (try? CodexOAuthCredentialsStore.load()) != nil
    }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        let fetcher = CodexLiteFetcher()
        let usage = try await fetcher.fetchUsage()
        let credits = try await fetcher.fetchCredits()
        return self.makeResult(
            usage: usage,
            credits: credits,
            sourceLabel: "oauth")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
