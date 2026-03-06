import CodexBarCore
import CodexBarMacroSupport
import SwiftUI

@ProviderImplementationRegistration
struct ClaudeProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .claude
    let supportsLoginFlow: Bool = true

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { context in
            var versionText = context.store.version(for: context.provider) ?? "not detected"
            if let parenRange = versionText.range(of: "(") {
                versionText = versionText[..<parenRange.lowerBound].trimmingCharacters(in: .whitespaces)
            }
            return "\(context.metadata.cliName) \(versionText)"
        }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.claudeUsageDataSource
        _ = settings.claudeOAuthKeychainPromptMode
        _ = settings.claudeOAuthKeychainReadStrategy
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .claude(context.settings.claudeSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func tokenAccountsVisibility(context: ProviderSettingsContext, support: TokenAccountSupport) -> Bool {
        _ = context
        _ = support
        return false
    }

    @MainActor
    func applyTokenAccountCookieSource(settings _: SettingsStore) {}

    @MainActor
    func defaultSourceLabel(context: ProviderSourceLabelContext) -> String? {
        context.settings.claudeUsageDataSource.sourceLabel
    }

    @MainActor
    func sourceMode(context: ProviderSourceModeContext) -> ProviderSourceMode {
        switch context.settings.claudeUsageDataSource {
        case .auto: .auto
        case .oauth: .oauth
        case .web, .cli: .auto
        }
    }

    @MainActor
    func settingsToggles(context: ProviderSettingsContext) -> [ProviderSettingsToggleDescriptor] {
        let subtitle = if context.settings.debugDisableKeychainAccess {
            "Inactive while \"Disable Keychain access\" is enabled in Advanced."
        } else {
            "Use /usr/bin/security to read Claude credentials and avoid CodexBar keychain prompts."
        }

        let promptFreeBinding = Binding(
            get: { context.settings.claudeOAuthPromptFreeCredentialsEnabled },
            set: { enabled in
                guard !context.settings.debugDisableKeychainAccess else { return }
                context.settings.claudeOAuthPromptFreeCredentialsEnabled = enabled
            })

        return [
            ProviderSettingsToggleDescriptor(
                id: "claude-oauth-prompt-free-credentials",
                title: "Avoid Keychain prompts (experimental)",
                subtitle: subtitle,
                binding: promptFreeBinding,
                statusText: nil,
                actions: [],
                isVisible: nil,
                onChange: nil,
                onAppDidBecomeActive: nil,
                onAppearWhenEnabled: nil),
        ]
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let usageBinding = Binding(
            get: { context.settings.claudeUsageDataSource.rawValue },
            set: { raw in
                context.settings.claudeUsageDataSource = ClaudeUsageDataSource(rawValue: raw) ?? .auto
            })
        let keychainPromptPolicyBinding = Binding(
            get: { context.settings.claudeOAuthKeychainPromptMode.rawValue },
            set: { raw in
                context.settings.claudeOAuthKeychainPromptMode = ClaudeOAuthKeychainPromptMode(rawValue: raw)
                    ?? .onlyOnUserAction
            })

        let usageOptions = ClaudeUsageDataSource.allCases.filter { $0 != .cli && $0 != .web }.map {
            ProviderSettingsPickerOption(id: $0.rawValue, title: $0.displayName)
        }
        let keychainPromptPolicyOptions: [ProviderSettingsPickerOption] = [
            ProviderSettingsPickerOption(
                id: ClaudeOAuthKeychainPromptMode.never.rawValue,
                title: "Never prompt"),
            ProviderSettingsPickerOption(
                id: ClaudeOAuthKeychainPromptMode.onlyOnUserAction.rawValue,
                title: "Only on user action"),
            ProviderSettingsPickerOption(
                id: ClaudeOAuthKeychainPromptMode.always.rawValue,
                title: "Always allow prompts"),
        ]
        let keychainPromptPolicySubtitle: () -> String? = {
            if context.settings.debugDisableKeychainAccess {
                return "Global Keychain access is disabled in Advanced, so this setting is currently inactive."
            }
            return "Controls Claude OAuth Keychain prompts when experimental reader mode is off."
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "claude-usage-source",
                title: "Usage source",
                subtitle: "Auto uses the same lightweight quota probe as Claude Code "
                    + "and falls back to local logs only when live auth is unavailable.",
                binding: usageBinding,
                options: usageOptions,
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    guard context.settings.claudeUsageDataSource == .auto else { return nil }
                    let label = context.store.sourceLabel(for: .claude)
                    return label == ClaudeUsageDataSource.auto.sourceLabel ? nil : label
                }),
            ProviderSettingsPickerDescriptor(
                id: "claude-keychain-prompt-policy",
                title: "Keychain prompt policy",
                subtitle: "Applies only to the Security.framework OAuth keychain reader.",
                dynamicSubtitle: keychainPromptPolicySubtitle,
                binding: keychainPromptPolicyBinding,
                options: keychainPromptPolicyOptions,
                isVisible: { context.settings.claudeOAuthKeychainReadStrategy == .securityFramework },
                isEnabled: { !context.settings.debugDisableKeychainAccess },
                onChange: nil),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        _ = context
        return []
    }

    @MainActor
    func runLoginFlow(context: ProviderLoginContext) async -> Bool {
        await context.controller.runClaudeLoginFlow()
        return true
    }

    @MainActor
    func appendUsageMenuEntries(context: ProviderMenuUsageContext, entries: inout [ProviderMenuEntry]) {
        let isLocalSource = context.store.sourceLabel(for: .claude)
            .localizedCaseInsensitiveContains(ClaudeUsageSourceLabels.local)
        if context.snapshot?.secondary == nil, isLocalSource {
            entries.append(.text("7-day quota is unavailable from local Claude logs.", .secondary))
        } else if context.snapshot?.secondary == nil {
            entries.append(.text("Weekly usage unavailable for this account.", .secondary))
        }

        if let cost = context.snapshot?.providerCost,
           context.settings.showOptionalCreditsAndExtraUsage,
           cost.currencyCode != "Quota"
        {
            let used = UsageFormatter.currencyString(cost.used, currencyCode: cost.currencyCode)
            let limit = UsageFormatter.currencyString(cost.limit, currencyCode: cost.currencyCode)
            entries.append(.text("Extra usage: \(used) / \(limit)", .primary))
        }
    }

    @MainActor
    func loginMenuAction(context: ProviderMenuLoginContext)
        -> (label: String, action: MenuDescriptor.MenuAction)?
    {
        guard self.shouldOpenTerminalForOAuthError(store: context.store) else { return nil }
        return ("Open Terminal", .openTerminal(command: "claude"))
    }

    @MainActor
    private func shouldOpenTerminalForOAuthError(store: UsageStore) -> Bool {
        guard store.error(for: .claude) != nil else { return false }
        let attempts = store.fetchAttempts(for: .claude)
        if attempts.contains(where: { $0.kind == .oauth && ($0.errorDescription?.isEmpty == false) }) {
            return true
        }
        if let error = store.error(for: .claude)?.lowercased(), error.contains("oauth") {
            return true
        }
        return false
    }
}
