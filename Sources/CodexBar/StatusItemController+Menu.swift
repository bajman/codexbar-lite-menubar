import AppKit
import CodexBarCore
import SwiftUI

extension ProviderSwitcherSelection {
    fileprivate var provider: UsageProvider? {
        switch self {
        case .overview:
            nil
        case let .provider(provider):
            provider
        }
    }
}

// MARK: - Model & data methods used by MenuPanelContentView

extension StatusItemController {
    static let menuCardBaseWidth: CGFloat = 310
    private static let maxOverviewProviders = SettingsStore.mergedOverviewProviderLimit

    // MARK: - Provider Resolution

    func resolvedMenuProvider(enabledProviders: [UsageProvider]? = nil) -> UsageProvider? {
        let enabled = enabledProviders ?? self.store.enabledProviders()
        if enabled.isEmpty { return .codex }
        // In split-icon mode, honour the icon the user actually clicked.
        if !self.shouldMergeIcons, let last = self.lastMenuProvider, enabled.contains(last) {
            #if DEBUG
            print("[resolvedMenuProvider] split-icon → lastMenuProvider=\(last)")
            #endif
            return last
        }
        if let selected = self.selectedMenuProvider, enabled.contains(selected) {
            #if DEBUG
            let message = "[resolvedMenuProvider] fallback → selectedMenuProvider=\(selected), " +
                "shouldMerge=\(self.shouldMergeIcons), " +
                "lastMenu=\(String(describing: self.lastMenuProvider)), " +
                "enabled=\(enabled)"
            print(message)
            #endif
            return selected
        }
        #if DEBUG
        let message = "[resolvedMenuProvider] default → enabled.first=\(String(describing: enabled.first)), " +
            "shouldMerge=\(self.shouldMergeIcons), " +
            "lastMenu=\(String(describing: self.lastMenuProvider))"
        print(message)
        #endif
        return enabled.first
    }

    func includesOverviewTab(enabledProviders: [UsageProvider]) -> Bool {
        !self.settings.resolvedMergedOverviewProviders(
            activeProviders: enabledProviders,
            maxVisibleProviders: Self.maxOverviewProviders).isEmpty
    }

    func resolvedSwitcherSelection(
        enabledProviders: [UsageProvider],
        includesOverview: Bool) -> ProviderSwitcherSelection
    {
        if includesOverview, self.settings.mergedMenuLastSelectedWasOverview {
            return .overview
        }
        return .provider(self.resolvedMenuProvider(enabledProviders: enabledProviders) ?? .codex)
    }

    // MARK: - Token Account Display

    func tokenAccountMenuDisplayModel(for provider: UsageProvider) -> TokenAccountMenuDisplayModel? {
        guard TokenAccountSupportCatalog.support(for: provider) != nil else { return nil }
        let accounts = self.settings.tokenAccounts(for: provider)
        guard accounts.count > 1 else { return nil }
        let activeIndex = self.settings.tokenAccountsData(for: provider)?.clampedActiveIndex() ?? 0
        let showAll = self.settings.showAllTokenAccountsInMenu
        let snapshots = showAll ? (self.store.accountSnapshots[provider] ?? []) : []
        return TokenAccountMenuDisplayModel(
            provider: provider,
            accounts: accounts,
            snapshots: snapshots,
            activeIndex: activeIndex,
            showAll: showAll,
            showSwitcher: !showAll)
    }

    // MARK: - OpenAI Web Context

    func openAIWebContextModel(
        currentProvider: UsageProvider,
        showAllTokenAccounts: Bool) -> OpenAIWebContextModel
    {
        let dashboard = self.store.openAIDashboard
        let openAIWebEligible = currentProvider == .codex &&
            self.store.openAIDashboardRequiresLogin == false &&
            dashboard != nil
        let hasCreditsHistory = openAIWebEligible && !(dashboard?.dailyBreakdown ?? []).isEmpty
        let hasUsageBreakdown = openAIWebEligible && !(dashboard?.usageBreakdown ?? []).isEmpty
        let hasCostHistory = self.settings.isCostUsageEffectivelyEnabled(for: currentProvider) &&
            (self.store.tokenSnapshot(for: currentProvider)?.daily.isEmpty == false)
        return OpenAIWebContextModel(
            hasUsageBreakdown: hasUsageBreakdown && !showAllTokenAccounts,
            hasCreditsHistory: hasCreditsHistory && !showAllTokenAccounts,
            hasCostHistory: hasCostHistory && !showAllTokenAccounts)
    }

    // MARK: - Switcher Icon & Weekly Metric

    func switcherIcon(for provider: UsageProvider) -> NSImage {
        if let brand = ProviderBrandIcon.image(for: provider) {
            return brand
        }

        let snapshot = self.store.snapshot(for: provider)
        let showUsed = self.settings.usageBarsShowUsed
        let primary = showUsed ? snapshot?.primary?.usedPercent : snapshot?.primary?.remainingPercent
        var weekly = showUsed ? snapshot?.secondary?.usedPercent : snapshot?.secondary?.remainingPercent
        if showUsed,
           provider == .warp,
           let remaining = snapshot?.secondary?.remainingPercent,
           remaining <= 0
        {
            weekly = 0
        }
        if showUsed,
           provider == .warp,
           let remaining = snapshot?.secondary?.remainingPercent,
           remaining > 0,
           weekly == 0
        {
            weekly = 0.0001
        }
        let credits = provider == .codex ? self.store.credits?.remaining : nil
        let stale = self.store.isStale(provider: provider)
        let style = self.store.style(for: provider)
        let indicator = self.store.statusIndicator(for: provider)
        let image = IconRenderer.makeIcon(
            primaryRemaining: primary,
            weeklyRemaining: weekly,
            creditsRemaining: credits,
            stale: stale,
            style: style,
            blink: 0,
            wiggle: 0,
            tilt: 0,
            statusIndicator: indicator)
        image.isTemplate = true
        return image
    }

    nonisolated static func switcherWeeklyMetricPercent(
        for provider: UsageProvider,
        snapshot: UsageSnapshot?,
        showUsed: Bool) -> Double?
    {
        let window = snapshot?.switcherWeeklyWindow(for: provider, showUsed: showUsed)
        guard let window else { return nil }
        return showUsed ? window.usedPercent : window.remainingPercent
    }

    func switcherWeeklyRemaining(for provider: UsageProvider) -> Double? {
        Self.switcherWeeklyMetricPercent(
            for: provider,
            snapshot: self.store.snapshot(for: provider),
            showUsed: self.settings.usageBarsShowUsed)
    }

    // MARK: - Card Model

    func menuCardModel(
        for provider: UsageProvider?,
        snapshotOverride: UsageSnapshot? = nil,
        errorOverride: String? = nil) -> UsageMenuCardView.Model?
    {
        let target = provider ?? self.store.enabledProviders().first ?? .codex
        let metadata = self.store.metadata(for: target)

        let snapshot = snapshotOverride ?? self.store.snapshot(for: target)
        let credits: CreditsSnapshot?
        let creditsError: String?
        let dashboard: OpenAIDashboardSnapshot?
        let dashboardError: String?
        let tokenSnapshot: CostUsageTokenSnapshot?
        let tokenError: String?
        if target == .codex, snapshotOverride == nil {
            credits = self.store.credits
            creditsError = self.store.lastCreditsError
            dashboard = self.store.openAIDashboardRequiresLogin ? nil : self.store.openAIDashboard
            dashboardError = self.store.lastOpenAIDashboardError
            tokenSnapshot = self.store.tokenSnapshot(for: target)
            tokenError = self.store.tokenError(for: target)
        } else if target == .claude || target == .vertexai, snapshotOverride == nil {
            credits = nil
            creditsError = nil
            dashboard = nil
            dashboardError = nil
            tokenSnapshot = self.store.tokenSnapshot(for: target)
            tokenError = self.store.tokenError(for: target)
        } else {
            credits = nil
            creditsError = nil
            dashboard = nil
            dashboardError = nil
            tokenSnapshot = nil
            tokenError = nil
        }

        let input = UsageMenuCardView.Model.Input(
            provider: target,
            metadata: metadata,
            snapshot: snapshot,
            credits: credits,
            creditsError: creditsError,
            dashboard: dashboard,
            dashboardError: dashboardError,
            tokenSnapshot: tokenSnapshot,
            tokenError: tokenError,
            account: self.account,
            isRefreshing: self.store.isRefreshing,
            lastError: errorOverride ?? self.store.error(for: target),
            usageBarsShowUsed: self.settings.usageBarsShowUsed,
            resetTimeDisplayStyle: self.settings.resetTimeDisplayStyle,
            tokenCostUsageEnabled: self.settings.isCostUsageEffectivelyEnabled(for: target),
            showOptionalCreditsAndExtraUsage: self.settings.showOptionalCreditsAndExtraUsage,
            hidePersonalInfo: self.settings.hidePersonalInfo,
            now: Date())
        return UsageMenuCardView.Model.make(input)
    }
}
