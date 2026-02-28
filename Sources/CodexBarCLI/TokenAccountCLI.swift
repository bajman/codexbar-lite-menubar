import CodexBarCore
import Foundation

struct TokenAccountCLISelection: Sendable {
    let label: String?
    let index: Int?
    let allAccounts: Bool

    var usesOverride: Bool {
        self.label != nil || self.index != nil || self.allAccounts
    }
}

enum TokenAccountCLIError: LocalizedError {
    case unsupported

    var errorDescription: String? {
        "Token account selection is not supported in CodexBar Lite."
    }
}

struct TokenAccountCLIContext {
    let selection: TokenAccountCLISelection
    let config: CodexBarConfig

    init(selection: TokenAccountCLISelection, config: CodexBarConfig, verbose _: Bool) throws {
        self.selection = selection
        self.config = config
    }

    func resolvedAccounts(for _: UsageProvider) throws -> [ProviderTokenAccount] {
        if self.selection.usesOverride {
            throw TokenAccountCLIError.unsupported
        }
        return []
    }

    func settingsSnapshot(for provider: UsageProvider, account _: ProviderTokenAccount?) -> ProviderSettingsSnapshot? {
        let preferred = self.preferredSourceMode(for: provider)
        switch provider {
        case .codex:
            let source: CodexUsageDataSource = preferred == .oauth ? .oauth : .auto
            return ProviderSettingsSnapshot.make(
                codex: ProviderSettingsSnapshot.CodexProviderSettings(usageDataSource: source))
        case .claude:
            let source: ClaudeUsageDataSource = preferred == .oauth ? .oauth : .auto
            return ProviderSettingsSnapshot.make(
                claude: ProviderSettingsSnapshot.ClaudeProviderSettings(usageDataSource: source))
        default:
            return nil
        }
    }

    func environment(
        base: [String: String],
        provider _: UsageProvider,
        account _: ProviderTokenAccount?) -> [String: String]
    {
        base
    }

    func applyAccountLabel(
        _ snapshot: UsageSnapshot,
        provider _: UsageProvider,
        account _: ProviderTokenAccount) -> UsageSnapshot
    {
        snapshot
    }

    func effectiveSourceMode(
        base: ProviderSourceMode,
        provider _: UsageProvider,
        account _: ProviderTokenAccount?) -> ProviderSourceMode
    {
        if base == .oauth { return .oauth }
        return .auto
    }

    func preferredSourceMode(for provider: UsageProvider) -> ProviderSourceMode {
        let source = self.config.providerConfig(for: provider)?.source
        return source == .oauth ? .oauth : .auto
    }
}
