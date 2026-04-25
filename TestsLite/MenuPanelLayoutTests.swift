import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct MenuPanelLayoutTests {
    private func makeConfigStore(suiteName: String) -> CodexBarConfigStore {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-tests", isDirectory: true)
            .appendingPathComponent(suiteName, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let fileURL = base.appendingPathComponent("config.json")
        try? FileManager.default.removeItem(at: fileURL)
        return CodexBarConfigStore(fileURL: fileURL)
    }

    private func makeSettings() -> SettingsStore {
        let suite = "MenuPanelLayoutTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configStore = self.makeConfigStore(suiteName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore)
        settings.statusChecksEnabled = false
        settings.refreshFrequency = RefreshFrequency.manual
        return settings
    }

    private func makeStore(settings: SettingsStore) -> UsageStore {
        let fetcher = UsageFetcher()
        return UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
    }

    private func containsScrollView(in view: NSView) -> Bool {
        if view is NSScrollView {
            return true
        }
        return view.subviews.contains { self.containsScrollView(in: $0) }
    }

    @Test
    func menuPanelRootDoesNotRenderViaScrollView() {
        guard #available(macOS 26, *) else { return }

        let settings = self.makeSettings()
        let store = self.makeStore(settings: settings)
        let fetcher = UsageFetcher()
        let view = MenuPanelContentView(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            cardWidth: 310,
            shouldMergeIcons: false,
            actions: nil,
            cardModelProvider: { _ in nil },
            switcherIconProvider: { _ in NSImage() },
            switcherWeeklyRemainingProvider: { _ in nil },
            includesOverviewProvider: { _ in false },
            resolvedSwitcherSelectionProvider: { providers, _ in .provider(providers.first ?? .codex) },
            resolvedMenuProviderFn: { nil },
            tokenAccountDisplayProvider: { _ in nil },
            openAIWebContextProvider: { _, _ in
                OpenAIWebContextModel(hasUsageBreakdown: false, hasCreditsHistory: false, hasCostHistory: false)
            })
            .environment(\.liquidGlassActive, false)

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 310, height: 900)
        hosting.layoutSubtreeIfNeeded()

        #expect(!self.containsScrollView(in: hosting))
    }

    @Test
    func actionInsetMatchesPrimaryContentInset() {
        #expect(MenuPanelMetrics.actionHorizontalPadding == MenuPanelMetrics.contentHorizontalPadding)
    }

    @Test
    func shellPaddingIsBalancedOnAllSides() {
        #expect(MenuPanelMetrics.shellTopPadding == MenuPanelMetrics.shellHorizontalPadding)
        #expect(MenuPanelMetrics.shellBottomPadding == MenuPanelMetrics.shellHorizontalPadding)
    }

    @Test
    func menuPanelUsesBorderlessChrome() {
        let panel = MenuPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 480))
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.styleMask.contains(.titled))
        #expect(!panel.styleMask.contains(.fullSizeContentView))
    }
}
