import CodexBarCore
import Foundation
import Testing

@Suite
struct WidgetCompatibilityTests {
    @Test
    func sanitizeDropsUnsupportedProviders() {
        let now = Date()
        let snapshot = WidgetSnapshot(
            entries: [
                WidgetSnapshot.ProviderEntry(
                    provider: .codex,
                    updatedAt: now,
                    primary: nil,
                    secondary: nil,
                    tertiary: nil,
                    creditsRemaining: nil,
                    codeReviewRemainingPercent: nil,
                    tokenUsage: nil,
                    dailyUsage: []),
                WidgetSnapshot.ProviderEntry(
                    provider: .cursor,
                    updatedAt: now,
                    primary: nil,
                    secondary: nil,
                    tertiary: nil,
                    creditsRemaining: nil,
                    codeReviewRemainingPercent: nil,
                    tokenUsage: nil,
                    dailyUsage: []),
            ],
            enabledProviders: [.cursor, .codex, .claude],
            generatedAt: now)

        let sanitized = WidgetSnapshotStore._sanitizeForTesting(snapshot)
        #expect(sanitized.entries.count == 1)
        #expect(sanitized.entries.first?.provider == .codex)
        #expect(sanitized.enabledProviders == [UsageProvider.codex, UsageProvider.claude])
    }
}
