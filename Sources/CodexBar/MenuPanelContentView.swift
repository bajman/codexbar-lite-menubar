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
    @Environment(\.liquidGlassActive) private var isActive

    private enum ExpandedChart: Equatable {
        case usageBreakdown
        case creditsHistory
        case costHistory
    }

    private var contentWidth: CGFloat {
        MenuPanelMetrics.contentWidth(for: self.cardWidth)
    }

    var body: some View {
        let enabledProviders = self.store.enabledProviders()
        let content = VStack(spacing: MenuPanelMetrics.sectionSpacing) {
            if self.shouldMergeIcons, enabledProviders.count > 1 {
                self.switcherSection(enabledProviders: enabledProviders)
            }

            self.cardSection(enabledProviders: enabledProviders)

            self.chartSection(enabledProviders: enabledProviders)

            Divider()

            self.actionSection(enabledProviders: enabledProviders)
        }
        .padding(.horizontal, MenuPanelMetrics.shellHorizontalPadding)
        .padding(.top, MenuPanelMetrics.shellTopPadding)
        .padding(.bottom, MenuPanelMetrics.shellBottomPadding)
        .frame(width: self.cardWidth)
        .menuGlassBackground(layer: .shell, cornerRadius: MenuPanelMetrics.shellCornerRadius, skipGlassEffect: true)

        #if DEBUG
        content
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(self.isActive ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .padding(6)
            }
        #else
        content
        #endif
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
                UsageMenuCardView(model: model, width: self.contentWidth)
            }
        }
    }

    @ViewBuilder
    private func overviewCards(enabledProviders: [UsageProvider]) -> some View {
        let overviewProviders = self.settings.resolvedMergedOverviewProviders(
            activeProviders: enabledProviders)
        VStack(spacing: MenuPanelMetrics.sectionSpacing) {
            ForEach(overviewProviders, id: \.self) { provider in
                if let model = self.cardModelProvider(provider) {
                    UsageMenuCardView(model: model, width: self.contentWidth)
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
                VStack(spacing: MenuPanelMetrics.sectionSpacing) {
                    if webContext.hasUsageBreakdown {
                        self.chartDisclosure(
                            title: "Usage Breakdown",
                            icon: "chart.bar.xaxis",
                            chart: .usageBreakdown)
                        {
                            if let breakdown = self.store.openAIDashboard?.dailyBreakdown {
                                UsageBreakdownChartMenuView(
                                    breakdown: breakdown, width: self.contentWidth)
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
                                    breakdown: breakdown, width: self.contentWidth)
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
                                    width: self.contentWidth)
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
            withAnimation(.snappy(duration: 0.22)) {
                self.expandedChart = self.expandedChart == chart ? nil : chart
            }
        } label: {
            HStack(spacing: MenuPanelMetrics.inlineSpacing) {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(self.expandedChart == chart ? 90 : 0))
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, MenuPanelMetrics.disclosureHorizontalPadding)
            .padding(.vertical, MenuPanelMetrics.disclosureVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if self.expandedChart == chart {
            content()
                .menuContentSurface(
                    cornerRadius: MenuPanelMetrics.sectionCornerRadius,
                    prominence: .subtle)
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

        VStack(spacing: MenuPanelMetrics.sectionSpacing) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                if self.isActionOnlySection(section) {
                    self.actionSectionView(section)
                } else {
                    self.infoSectionView(section)
                }
            }
        }
        .padding(.bottom, MenuPanelMetrics.footerBottomPadding)
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

    private func isActionOnlySection(_ section: MenuDescriptor.Section) -> Bool {
        section.entries.allSatisfy { entry in
            if case .action = entry { return true }
            return false
        }
    }

    @ViewBuilder
    private func actionSectionView(_ section: MenuDescriptor.Section) -> some View {
        let content = VStack(spacing: MenuPanelMetrics.compactSpacing) {
            ForEach(Array(section.entries.enumerated()), id: \.offset) { _, entry in
                self.entryView(entry)
            }
        }

        if LiquidGlassAvailability.shouldApplyGlass {
            GlassEffectContainer(spacing: MenuPanelMetrics.compactSpacing) {
                content
            }
        } else {
            content
        }
    }

    private func infoSectionView(_ section: MenuDescriptor.Section) -> some View {
        VStack(spacing: MenuPanelMetrics.compactSpacing) {
            ForEach(Array(section.entries.enumerated()), id: \.offset) { _, entry in
                self.entryView(entry)
            }
        }
        .padding(.horizontal, MenuPanelMetrics.compactSurfacePadding)
        .padding(.vertical, MenuPanelMetrics.compactSurfacePadding)
        .menuContentSurface(
            cornerRadius: MenuPanelMetrics.sectionCornerRadius,
            prominence: .subtle)
    }

    @ViewBuilder
    private func textEntryView(text: String, style: MenuDescriptor.TextStyle) -> some View {
        switch style {
        case .headline:
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, MenuPanelMetrics.compactSpacing)
        case .primary:
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, MenuPanelMetrics.compactSpacing)
        case .secondary:
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, MenuPanelMetrics.compactSpacing)
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
                        .frame(width: MenuPanelMetrics.actionIconWidth, alignment: .center)
                        .symbolRenderingMode(.hierarchical)
                }
                Text(title)
                Spacer()
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, MenuPanelMetrics.actionVerticalPadding)
            .contentShape(Rectangle())
        }
        .menuPanelActionButtonStyle()
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

private struct MenuPanelActionButtonStyle: ViewModifier {
    @Environment(\.liquidGlassActive) private var isActive

    func body(content: Content) -> some View {
        if #available(macOS 26, *), self.isActive, LiquidGlassAvailability.shouldApplyGlass {
            content.buttonStyle(.glass)
        } else {
            content
        }
    }
}

extension View {
    fileprivate func menuPanelActionButtonStyle() -> some View {
        self.modifier(MenuPanelActionButtonStyle())
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
