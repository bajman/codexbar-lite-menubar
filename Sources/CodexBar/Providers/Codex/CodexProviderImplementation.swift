import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct CodexProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .codex
    let supportsLoginFlow: Bool = true

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { context in
            context.store.version(for: context.provider) ?? "not detected"
        }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.codexUsageDataSource
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .codex(context.settings.codexSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func defaultSourceLabel(context: ProviderSourceLabelContext) -> String? {
        context.settings.codexUsageDataSource.rawValue
    }

    @MainActor
    func sourceMode(context: ProviderSourceModeContext) -> ProviderSourceMode {
        switch context.settings.codexUsageDataSource {
        case .auto: .auto
        case .oauth: .oauth
        case .cli: .auto
        }
    }

    func makeRuntime() -> (any ProviderRuntime)? {
        CodexProviderRuntime()
    }

    @MainActor
    func settingsToggles(context: ProviderSettingsContext) -> [ProviderSettingsToggleDescriptor] {
        _ = context
        return []
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let usageBinding = Binding(
            get: { context.settings.codexUsageDataSource.rawValue },
            set: { raw in
                context.settings.codexUsageDataSource = CodexUsageDataSource(rawValue: raw) ?? .auto
            })
        let usageOptions = CodexUsageDataSource.allCases.filter { $0 != .cli }.map {
            ProviderSettingsPickerOption(id: $0.rawValue, title: $0.displayName)
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "codex-usage-source",
                title: "Usage source",
                subtitle: "Lite mode allows direct OAuth usage fetch only.",
                binding: usageBinding,
                options: usageOptions,
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    guard context.settings.codexUsageDataSource == .auto else { return nil }
                    let label = context.store.sourceLabel(for: .codex)
                    return label == "auto" ? nil : label
                }),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        _ = context
        return []
    }

    @MainActor
    func appendUsageMenuEntries(context: ProviderMenuUsageContext, entries: inout [ProviderMenuEntry]) {
        guard context.settings.showOptionalCreditsAndExtraUsage,
              context.metadata.supportsCredits
        else { return }

        if let credits = context.store.credits {
            entries.append(.text("Credits: \(UsageFormatter.creditsString(from: credits.remaining))", .primary))
            if let latest = credits.events.first {
                entries.append(.text("Last spend: \(UsageFormatter.creditEventSummary(latest))", .secondary))
            }
        } else {
            let hint = context.store.lastCreditsError ?? context.metadata.creditsHint
            entries.append(.text(hint, .secondary))
        }
    }

    @MainActor
    func runLoginFlow(context: ProviderLoginContext) async -> Bool {
        await context.controller.runCodexLoginFlow()
        return true
    }
}
