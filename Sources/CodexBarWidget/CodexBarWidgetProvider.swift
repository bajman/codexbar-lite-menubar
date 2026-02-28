import CodexBarCore
import SwiftUI
import WidgetKit

enum CompactMetric: String {
    case credits
    case todayCost
    case last30DaysCost
}

struct CodexBarWidgetEntry: TimelineEntry {
    let date: Date
    let provider: UsageProvider
    let snapshot: WidgetSnapshot
}

struct CodexBarCompactEntry: TimelineEntry {
    let date: Date
    let provider: UsageProvider
    let metric: CompactMetric
    let snapshot: WidgetSnapshot
}

struct CodexBarSwitcherEntry: TimelineEntry {
    let date: Date
    let provider: UsageProvider
    let availableProviders: [UsageProvider]
    let snapshot: WidgetSnapshot
}

struct CodexBarTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexBarWidgetEntry {
        let snapshot = WidgetPreviewData.snapshot()
        let providers = WidgetProviderSupport.availableProviders(from: snapshot)
        return CodexBarWidgetEntry(
            date: Date(),
            provider: providers.first ?? .codex,
            snapshot: snapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexBarWidgetEntry) -> Void) {
        completion(self.makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexBarWidgetEntry>) -> Void) {
        let entry = self.makeEntry()
        let refresh = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func makeEntry() -> CodexBarWidgetEntry {
        let snapshot = WidgetSnapshotStore.load() ?? WidgetProviderSupport.emptySnapshot()
        let providers = WidgetProviderSupport.availableProviders(from: snapshot)
        let selected = WidgetProviderSupport.resolveSelectedProvider(availableProviders: providers)
        return CodexBarWidgetEntry(
            date: Date(),
            provider: selected,
            snapshot: snapshot)
    }
}

struct CodexBarSwitcherTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexBarSwitcherEntry {
        let snapshot = WidgetPreviewData.snapshot()
        let providers = self.availableProviders(from: snapshot)
        return CodexBarSwitcherEntry(
            date: Date(),
            provider: providers.first ?? .codex,
            availableProviders: providers,
            snapshot: snapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexBarSwitcherEntry) -> Void) {
        completion(self.makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexBarSwitcherEntry>) -> Void) {
        let entry = self.makeEntry()
        let refresh = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func makeEntry() -> CodexBarSwitcherEntry {
        let snapshot = WidgetSnapshotStore.load() ?? WidgetProviderSupport.emptySnapshot()
        let providers = self.availableProviders(from: snapshot)
        let stored = WidgetSelectionStore.loadSelectedProvider()
        let selected = providers.first { $0 == stored } ?? providers.first ?? .codex
        if selected != stored {
            WidgetSelectionStore.saveSelectedProvider(selected)
        }
        return CodexBarSwitcherEntry(
            date: Date(),
            provider: selected,
            availableProviders: providers,
            snapshot: snapshot)
    }

    private func availableProviders(from snapshot: WidgetSnapshot) -> [UsageProvider] {
        WidgetProviderSupport.availableProviders(from: snapshot)
    }
}

struct CodexBarCompactTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexBarCompactEntry {
        let snapshot = WidgetPreviewData.snapshot()
        let providers = WidgetProviderSupport.availableProviders(from: snapshot)
        return CodexBarCompactEntry(
            date: Date(),
            provider: providers.first ?? .codex,
            metric: .credits,
            snapshot: snapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexBarCompactEntry) -> Void) {
        completion(self.makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexBarCompactEntry>) -> Void) {
        let entry = self.makeEntry()
        let refresh = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func makeEntry() -> CodexBarCompactEntry {
        let snapshot = WidgetSnapshotStore.load() ?? WidgetProviderSupport.emptySnapshot()
        let providers = WidgetProviderSupport.availableProviders(from: snapshot)
        let selected = WidgetProviderSupport.resolveSelectedProvider(availableProviders: providers)
        return CodexBarCompactEntry(
            date: Date(),
            provider: selected,
            metric: .credits,
            snapshot: snapshot)
    }
}

enum WidgetProviderSupport {
    static func emptySnapshot() -> WidgetSnapshot {
        WidgetSnapshot(entries: [], enabledProviders: [.codex, .claude], generatedAt: Date())
    }

    static func availableProviders(from snapshot: WidgetSnapshot) -> [UsageProvider] {
        let order: [UsageProvider] = [.codex, .claude]
        let supported: Set<UsageProvider> = [.codex, .claude]
        let fromEnabled = snapshot.enabledProviders.filter { supported.contains($0) }
        let fromEntries = snapshot.entries.map(\.provider).filter { supported.contains($0) }
        let combined = Set(fromEnabled).union(fromEntries)
        if combined.isEmpty {
            return order
        }
        return order.filter { combined.contains($0) }
    }

    static func resolveSelectedProvider(availableProviders: [UsageProvider]) -> UsageProvider {
        let stored = WidgetSelectionStore.loadSelectedProvider()
        let selected = availableProviders.first { $0 == stored } ?? availableProviders.first ?? .codex
        if selected != stored {
            WidgetSelectionStore.saveSelectedProvider(selected)
        }
        return selected
    }
}

enum WidgetPreviewData {
    static func snapshot() -> WidgetSnapshot {
        let primary = RateWindow(usedPercent: 35, windowMinutes: nil, resetsAt: nil, resetDescription: "Resets in 4h")
        let secondary = RateWindow(usedPercent: 60, windowMinutes: nil, resetsAt: nil, resetDescription: "Resets in 3d")
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .codex,
            updatedAt: Date(),
            primary: primary,
            secondary: secondary,
            tertiary: nil,
            creditsRemaining: 1243.4,
            codeReviewRemainingPercent: 78,
            tokenUsage: WidgetSnapshot.TokenUsageSummary(
                sessionCostUSD: 12.4,
                sessionTokens: 420_000,
                last30DaysCostUSD: 923.8,
                last30DaysTokens: 12_400_000),
            dailyUsage: [
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-01", totalTokens: 120_000, costUSD: 15.2),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-02", totalTokens: 80000, costUSD: 10.1),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-03", totalTokens: 140_000, costUSD: 17.9),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-04", totalTokens: 90000, costUSD: 11.4),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-05", totalTokens: 160_000, costUSD: 19.8),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-06", totalTokens: 70000, costUSD: 8.9),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-07", totalTokens: 110_000, costUSD: 13.7),
            ])
        return WidgetSnapshot(entries: [entry], generatedAt: Date())
    }
}
