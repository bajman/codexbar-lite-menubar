import AppKit
import CodexBarCore
import SwiftUI

// MARK: - Actions protocol for panel content

@MainActor
protocol MenuPanelActions: AnyObject {
    func refreshNow()
    func refreshAugmentSession()
    func installUpdate()
    func openDashboard()
    func openStatusPage()
    func openCreditsPurchase()
    func showSettingsGeneral()
    func showSettingsAbout()
    func quit()
    func runSwitchAccount(provider: UsageProvider)
    func openTerminal(command: String)
    func openLoginToProvider(url: String)
    func copyError(_ message: String)
    func dismissPanel()
}

// MARK: - Root content view

@available(macOS 26, *)
struct MenuPanelContentView: View {
    let store: UsageStore
    let settings: SettingsStore
    let account: AccountInfo
    let updater: UpdaterProviding
    let cardWidth: CGFloat
    let shouldMergeIcons: Bool
    weak var actions: (any MenuPanelActions)?

    let cardModelProvider: (UsageProvider?) -> UsageMenuCardView.Model?
    let switcherIconProvider: (UsageProvider) -> NSImage
    let switcherWeeklyRemainingProvider: (UsageProvider) -> Double?
    let includesOverviewProvider: ([UsageProvider]) -> Bool
    let resolvedSwitcherSelectionProvider: ([UsageProvider], Bool) -> ProviderSwitcherSelection
    let resolvedMenuProviderFn: () -> UsageProvider?
    let tokenAccountDisplayProvider: (UsageProvider) -> TokenAccountMenuDisplayModel?
    let openAIWebContextProvider: (UsageProvider, Bool) -> OpenAIWebContextModel

    @State private var switcherSelection: ProviderSwitcherSelection?
    @State private var expandedChart: ExpandedChart?

    private enum ExpandedChart: Equatable {
        case usageBreakdown
        case creditsHistory
        case costHistory
    }

    var body: some View {
        let enabledProviders = self.store.enabledProviders()
        let content = VStack(spacing: 8) {
            if self.shouldMergeIcons, enabledProviders.count > 1 {
                self.switcherSection(enabledProviders: enabledProviders)
            }

            self.cardSection(enabledProviders: enabledProviders)

            self.chartSection(enabledProviders: enabledProviders)

            Divider()
                .padding(.horizontal, 12)

            self.actionSection(enabledProviders: enabledProviders)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: self.cardWidth)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        content
    }

    // MARK: - Provider Switcher

    @ViewBuilder
    private func switcherSection(enabledProviders: [UsageProvider]) -> some View {
        let includesOverview = self.includesOverviewProvider(enabledProviders)
        let selection = self.switcherSelection ?? self.resolvedSwitcherSelectionProvider(
            enabledProviders, includesOverview)

        GlassProviderSwitcherView(
            providers: enabledProviders,
            selected: selection,
            includesOverview: includesOverview,
            showsIcons: self.settings.switcherShowsIcons,
            iconProvider: self.switcherIconProvider,
            weeklyRemainingProvider: self.switcherWeeklyRemainingProvider,
            onSelect: { newSelection in
                self.switcherSelection = newSelection
                if case let .provider(provider) = newSelection {
                    self.settings.selectedMenuProvider = provider
                }
                self.expandedChart = nil
            })

        if let currentProvider = self.resolvedCurrentProvider(
            enabledProviders: enabledProviders, isOverview: selection == .overview)
        {
            self.tokenAccountSection(for: currentProvider)
        }
    }

    // MARK: - Token Account Switcher

    @ViewBuilder
    private func tokenAccountSection(for provider: UsageProvider) -> some View {
        if let display = self.tokenAccountDisplayProvider(provider), display.showSwitcher {
            GlassTokenAccountSwitcherView(
                accounts: display.accounts,
                selectedIndex: display.activeIndex,
                onSelect: { index in
                    self.settings.setActiveTokenAccountIndex(index, for: provider)
                })
        }
    }

    // MARK: - Usage Cards

    @ViewBuilder
    private func cardSection(enabledProviders: [UsageProvider]) -> some View {
        let isOverview = self.switcherSelection == .overview
        if isOverview {
            self.overviewCards(enabledProviders: enabledProviders)
        } else {
            let provider = self.resolvedCurrentProvider(
                enabledProviders: enabledProviders, isOverview: false)
            if let provider, let model = self.cardModelProvider(provider) {
                UsageMenuCardView(model: model, width: self.cardWidth - 24)
            }
        }
    }

    @ViewBuilder
    private func overviewCards(enabledProviders: [UsageProvider]) -> some View {
        let overviewProviders = self.settings.resolvedMergedOverviewProviders(
            activeProviders: enabledProviders)
        VStack(spacing: 4) {
            ForEach(overviewProviders, id: \.self) { provider in
                if let model = self.cardModelProvider(provider) {
                    UsageMenuCardView(model: model, width: self.cardWidth - 24)
                }
            }
        }
    }

    // MARK: - Chart Sections (inline disclosure)

    @ViewBuilder
    private func chartSection(enabledProviders: [UsageProvider]) -> some View {
        let isOverview = self.switcherSelection == .overview
        if let provider = self.resolvedCurrentProvider(
            enabledProviders: enabledProviders, isOverview: isOverview)
        {
            let tokenDisplay = self.tokenAccountDisplayProvider(provider)
            let showAllAccounts = tokenDisplay?.showAll ?? false
            let webContext = self.openAIWebContextProvider(provider, showAllAccounts)

            if webContext.hasUsageBreakdown || webContext.hasCreditsHistory || webContext.hasCostHistory {
                VStack(spacing: 4) {
                    if webContext.hasUsageBreakdown {
                        self.chartDisclosure(
                            title: "Usage Breakdown",
                            icon: "chart.bar.xaxis",
                            chart: .usageBreakdown)
                        {
                            if let breakdown = self.store.openAIDashboard?.dailyBreakdown {
                                UsageBreakdownChartMenuView(
                                    breakdown: breakdown, width: self.cardWidth - 24)
                            }
                        }
                    }
                    if webContext.hasCreditsHistory {
                        self.chartDisclosure(
                            title: "Credits History",
                            icon: "dollarsign.circle",
                            chart: .creditsHistory)
                        {
                            if let breakdown = self.store.openAIDashboard?.dailyBreakdown {
                                CreditsHistoryChartMenuView(
                                    breakdown: breakdown, width: self.cardWidth - 24)
                            }
                        }
                    }
                    if webContext.hasCostHistory {
                        self.chartDisclosure(
                            title: "Cost History",
                            icon: "chart.line.uptrend.xyaxis",
                            chart: .costHistory)
                        {
                            if let snapshot = self.store.tokenSnapshot(for: provider) {
                                CostHistoryChartMenuView(
                                    provider: provider,
                                    daily: snapshot.daily,
                                    totalCostUSD: snapshot.last30DaysCostUSD,
                                    width: self.cardWidth - 24)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chartDisclosure(
        title: String,
        icon: String,
        chart: ExpandedChart,
        @ViewBuilder content: @escaping () -> some View) -> some View
    {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.expandedChart = self.expandedChart == chart ? nil : chart
            }
        } label: {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline)
                Spacer()
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(self.expandedChart == chart ? 90 : 0))
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if self.expandedChart == chart {
            content()
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private func actionSection(enabledProviders: [UsageProvider]) -> some View {
        let isOverview = self.switcherSelection == .overview
        let currentProvider = self.resolvedCurrentProvider(
            enabledProviders: enabledProviders, isOverview: isOverview)
        let sections = MenuDescriptor.buildActionAndMetaSections(
            provider: currentProvider,
            store: self.store,
            account: self.account,
            updateReady: self.updater.updateStatus.isUpdateReady,
            includeContextualActions: !isOverview)

        VStack(spacing: 2) {
            ForEach(Array(sections.enumerated()), id: \.offset) { sectionIndex, section in
                ForEach(Array(section.entries.enumerated()), id: \.offset) { _, entry in
                    self.entryView(entry)
                }
                if sectionIndex < sections.count - 1 {
                    Divider()
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private func entryView(_ entry: MenuDescriptor.Entry) -> some View {
        switch entry {
        case let .text(text, style):
            self.textEntryView(text: text, style: style)
        case let .action(title, action):
            self.actionButton(title: title, action: action)
        case .divider:
            Divider()
                .padding(.horizontal, 4)
        }
    }

    private func textEntryView(text: String, style: MenuDescriptor.TextStyle) -> some View {
        switch style {
        case .headline:
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        case .primary:
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        case .secondary:
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    private func actionButton(title: String, action: MenuDescriptor.MenuAction) -> some View {
        Button {
            self.actions?.dismissPanel()
            self.executeAction(action)
        } label: {
            HStack(spacing: 8) {
                if let icon = action.systemImageName {
                    Image(systemName: icon)
                        .frame(width: 16)
                        .symbolRenderingMode(.hierarchical)
                }
                Text(title)
                Spacer()
            }
            .font(.subheadline)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPanelActionButtonStyle())
    }

    private func executeAction(_ action: MenuDescriptor.MenuAction) {
        switch action {
        case .refresh:
            self.actions?.refreshNow()
        case .refreshAugmentSession:
            self.actions?.refreshAugmentSession()
        case .installUpdate:
            self.actions?.installUpdate()
        case .dashboard:
            self.actions?.openDashboard()
        case .statusPage:
            self.actions?.openStatusPage()
        case let .switchAccount(provider):
            self.actions?.runSwitchAccount(provider: provider)
        case let .openTerminal(command):
            self.actions?.openTerminal(command: command)
        case let .loginToProvider(url):
            self.actions?.openLoginToProvider(url: url)
        case .settings:
            self.actions?.showSettingsGeneral()
        case .about:
            self.actions?.showSettingsAbout()
        case .quit:
            self.actions?.quit()
        case let .copyError(message):
            self.actions?.copyError(message)
        }
    }

    // MARK: - Helpers

    private func resolvedCurrentProvider(
        enabledProviders: [UsageProvider], isOverview: Bool) -> UsageProvider?
    {
        if isOverview {
            return self.resolvedMenuProviderFn()
        }
        if case let .provider(p) = self.switcherSelection, enabledProviders.contains(p) {
            return p
        }
        return self.resolvedMenuProviderFn()
    }
}

// MARK: - Action Button Style

private struct MenuPanelActionButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(self.isHovered ? Color.primary.opacity(0.08) : .clear))
            .onHover { hovering in
                self.isHovered = hovering
            }
    }
}

// MARK: - View models for data passed from StatusItemController

struct TokenAccountMenuDisplayModel {
    let provider: UsageProvider
    let accounts: [ProviderTokenAccount]
    let snapshots: [TokenAccountUsageSnapshot]
    let activeIndex: Int
    let showAll: Bool
    let showSwitcher: Bool
}

struct OpenAIWebContextModel {
    let hasUsageBreakdown: Bool
    let hasCreditsHistory: Bool
    let hasCostHistory: Bool
}
