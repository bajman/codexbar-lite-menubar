import CodexBarCore
import SwiftUI
import WidgetKit


private enum WidgetSurfaceStyle {
    case usage
    case history
    case compact
    case switcher
}

private enum WidgetLiquidGlass {
    static let radius: CGFloat = 19
    static let edgeWidth: CGFloat = 1.0

    static func accent(for provider: UsageProvider?) -> Color {
        guard let provider else { return Color.secondary.opacity(0.24) }
        return WidgetColors.color(for: provider)
    }

    static func borderAlpha(for renderingMode: WidgetRenderingMode) -> Double {
        renderingMode == .accented ? 0.34 : 0.22
    }

    static func highlightAlpha(for renderingMode: WidgetRenderingMode) -> Double {
        renderingMode == .accented ? 0.30 : 0.16
    }

    static func baseOpacity(for style: WidgetSurfaceStyle, renderingMode: WidgetRenderingMode) -> Double {
        switch style {
        case .compact:
            return renderingMode == .accented ? 0.92 : 0.76
        case .history:
            return renderingMode == .accented ? 0.90 : 0.72
        case .switcher:
            return renderingMode == .accented ? 0.88 : 0.70
        case .usage:
            return renderingMode == .accented ? 0.90 : 0.74
        }
    }

    static func accentWashOpacity(for style: WidgetSurfaceStyle, renderingMode: WidgetRenderingMode) -> Double {
        switch style {
        case .compact:
            return renderingMode == .accented ? 0.42 : 0.30
        case .history:
            return renderingMode == .accented ? 0.38 : 0.26
        case .switcher:
            return renderingMode == .accented ? 0.44 : 0.28
        case .usage:
            return renderingMode == .accented ? 0.40 : 0.28
        }
    }
}

private struct WidgetSurface<Content: View>: View {
    @Environment(\.widgetContentMargins) private var margins
    @Environment(\.showsWidgetContainerBackground) private var showsWidgetContainerBackground
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    let provider: UsageProvider?
    let style: WidgetSurfaceStyle
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            if self.showsWidgetContainerBackground {
                LiquidGlassFill(
                    provider: self.provider,
                    renderingMode: self.renderingMode,
                    style: self.style)
            }
            self.content
        }
        .padding(.top, self.margins.top + 8)
        .padding(.bottom, self.margins.bottom + 8)
        .padding(.leading, self.margins.leading + 8)
        .padding(.trailing, self.margins.trailing + 8)
        .overlay {
            RoundedRectangle(cornerRadius: WidgetLiquidGlass.radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(self.colorScheme == .dark ? 0.56 : 0.34),
                            Color.white.opacity(self.colorScheme == .dark ? 0.2 : 0.06),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing),
                    lineWidth: WidgetLiquidGlass.edgeWidth)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: WidgetLiquidGlass.radius, style: .continuous)
                .trim(from: 0.0, to: 0.96)
                .stroke(
                    self.glowColor.opacity(WidgetLiquidGlass.highlightAlpha(for: self.renderingMode)),
                    lineWidth: self.style == .compact ? 0.55 : 0.4)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            RoundedRectangle(cornerRadius: WidgetLiquidGlass.radius, style: .continuous)
                .trim(from: 0.05, to: 0.95)
                .stroke(
                    Color.white.opacity(self.renderingMode == .accented ? 0.14 : 0.08),
                    lineWidth: self.style == .compact ? 0.45 : 0.35)
                .blur(radius: 0.3)
                .offset(y: 0.25)
                .allowsHitTesting(false)
        }
        .mask(RoundedRectangle(cornerRadius: WidgetLiquidGlass.radius, style: .continuous))
        .shadow(
            color: self.glowColor.opacity(self.renderingMode == .accented ? 0.28 : 0.16),
            radius: self.renderingMode == .accented ? 20 : 14,
            x: 0,
            y: 8)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var glowColor: Color {
        if let provider {
            return WidgetColors.color(for: provider)
        }
        return Color.secondary
    }
}

private struct LiquidGlassFill: View {
    let provider: UsageProvider?
    let renderingMode: WidgetRenderingMode
    let style: WidgetSurfaceStyle
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: WidgetLiquidGlass.radius, style: .continuous)
                .fill(.ultraThinMaterial.opacity(WidgetLiquidGlass.baseOpacity(for: self.style, renderingMode: self.renderingMode)))
            RoundedRectangle(cornerRadius: WidgetLiquidGlass.radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(self.style == .compact ? 0.26 : 0.18),
                            Color.clear,
                            Color.white.opacity(self.style == .history ? 0.12 : 0.08),
                        ],
                        startPoint: .top,
                        endPoint: .bottom))
                .blendMode(.screen)
                .opacity(self.renderingMode == .accented ? 0.98 : 0.86)
            RoundedRectangle(cornerRadius: WidgetLiquidGlass.radius, style: .continuous)
                .fill(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(self.colorScheme == .dark ? 0.28 : 0.20), location: 0.0),
                            .init(color: .clear, location: 0.30),
                            .init(color: Color.white.opacity(0.06), location: 0.58),
                            .init(color: .clear, location: 0.90),
                        ]),
                        center: .topLeading))
                .opacity(self.style == .switcher ? 0.42 : 0.34)
            if let provider {
                let accent = WidgetColors.color(for: provider)
                RoundedRectangle(cornerRadius: WidgetLiquidGlass.radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(WidgetLiquidGlass.accentWashOpacity(for: self.style, renderingMode: self.renderingMode)),
                                .clear,
                                accent.opacity(self.renderingMode == .accented ? 0.30 : 0.20),
                                .clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                    .blendMode(.screen)
                    .overlay(
                        RoundedRectangle(cornerRadius: WidgetLiquidGlass.radius, style: .continuous)
                            .stroke(accent.opacity(WidgetLiquidGlass.borderAlpha(for: self.renderingMode)), lineWidth: WidgetLiquidGlass.edgeWidth)
                    )
            }
            self.styleOverlay
            RoundedRectangle(cornerRadius: WidgetLiquidGlass.radius, style: .continuous)
                .fill(Color.white.opacity(self.colorScheme == .dark ? 0.18 : 0.10))
                .blendMode(.softLight)
                .mask(
                    RoundedRectangle(cornerRadius: WidgetLiquidGlass.radius, style: .continuous)
                )
            RoundedRectangle(cornerRadius: WidgetLiquidGlass.radius, style: .continuous)
                .stroke(Color.white.opacity(self.colorScheme == .dark ? 0.26 : 0.16), lineWidth: 0.9)
                .blendMode(.plusLighter)
                .blur(radius: 0.3)
                .opacity(self.renderingMode == .accented ? 0.7 : 0.45)
                .mask(
                    RoundedRectangle(cornerRadius: WidgetLiquidGlass.radius, style: .continuous)
                )
            if #available(macOS 26, *) {
                RoundedRectangle(cornerRadius: WidgetLiquidGlass.radius, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: WidgetLiquidGlass.radius, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var styleOverlay: some View {
        switch self.style {
        case .usage:
            RoundedRectangle(cornerRadius: WidgetLiquidGlass.radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.20),
                            .clear,
                            Color.white.opacity(0.10),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
                .blendMode(.screen)
                .opacity(self.renderingMode == .accented ? 0.7 : 0.45)
        case .history:
            RoundedRectangle(cornerRadius: WidgetLiquidGlass.radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.16),
                            Color.clear,
                        ],
                        startPoint: .bottom,
                        endPoint: .top))
                .opacity(self.renderingMode == .accented ? 0.75 : 0.55)
            RoundedRectangle(cornerRadius: WidgetLiquidGlass.radius, style: .continuous)
                .stroke(
                    Color.white.opacity(self.colorScheme == .dark ? 0.22 : 0.12),
                    style: StrokeStyle(lineWidth: 0.45, dash: [6, 8]))
                .opacity(0.25)
        case .compact:
            RoundedRectangle(cornerRadius: WidgetLiquidGlass.radius, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            .clear,
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 160))
                .opacity(self.renderingMode == .accented ? 0.9 : 0.6)
        case .switcher:
            RoundedRectangle(cornerRadius: WidgetLiquidGlass.radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.26),
                            Color.white.opacity(0.04),
                            .clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom))
                .opacity(self.renderingMode == .accented ? 0.85 : 0.6)
        }
    }
}

private struct GlassMetricPill: View {
    let text: String
    let color: Color
    let emphasized: Bool

    var body: some View {
        Text(self.text)
            .font(.caption2)
            .fontWeight(self.emphasized ? .semibold : .regular)
            .foregroundStyle(self.emphasized ? .primary : .secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(.thinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(color.opacity(self.emphasized ? 0.42 : 0.16), lineWidth: self.emphasized ? 1 : 0.6)))
            .overlay(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), .clear],
                            startPoint: .top,
                            endPoint: .bottom))
                    .padding(.horizontal, 3)
                    .frame(height: 1.5)
                    .offset(y: -1.5)
                    .allowsHitTesting(false))
            .blendMode(.plusLighter)
    }
}

private struct GlassSurfaceLabel: View {
    let text: String
    let accent: Color

    var body: some View {
        Text(self.text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [self.accent.opacity(0.34), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom),
                                lineWidth: 0.55)))
            .accessibilityHidden(true)
    }
}

private struct LiquidGlassChartBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.6))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.16),
                                .clear,
                                Color.white.opacity(0.08),
                            ],
                            startPoint: .top,
                            endPoint: .bottom)))
            .opacity(0.9)
            .allowsHitTesting(false)
    }
}
struct CodexBarUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodexBarWidgetEntry

    var body: some View {
        let providerEntry = self.entry.snapshot.entries.first { $0.provider == self.entry.provider }
        WidgetSurface(provider: providerEntry?.provider, style: .usage) {
            if let providerEntry {
                self.content(providerEntry: providerEntry)
            } else {
                self.emptyState
            }
        }
    }

    @ViewBuilder
    private func content(providerEntry: WidgetSnapshot.ProviderEntry) -> some View {
        switch self.family {
        case .systemSmall:
            SmallUsageView(entry: providerEntry, showUsed: self.entry.snapshot.usageBarsShowUsed)
        case .systemMedium:
            MediumUsageView(entry: providerEntry, showUsed: self.entry.snapshot.usageBarsShowUsed)
        default:
            LargeUsageView(entry: providerEntry, showUsed: self.entry.snapshot.usageBarsShowUsed)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Open CodexBar")
                .font(.body)
                .fontWeight(.semibold)
            Text("Usage data will appear once the app refreshes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}

struct CodexBarHistoryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodexBarWidgetEntry

    var body: some View {
        let providerEntry = self.entry.snapshot.entries.first { $0.provider == self.entry.provider }
        WidgetSurface(provider: providerEntry?.provider, style: .history) {
            if let providerEntry {
                HistoryView(
                    entry: providerEntry,
                    isLarge: self.family == .systemLarge,
                    showUsed: self.entry.snapshot.usageBarsShowUsed)
            } else {
                self.emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Open CodexBar")
                .font(.body)
                .fontWeight(.semibold)
            Text("Usage history will appear after a refresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}

struct CodexBarCompactWidgetView: View {
    let entry: CodexBarCompactEntry

    var body: some View {
        let providerEntry = self.entry.snapshot.entries.first { $0.provider == self.entry.provider }
        WidgetSurface(provider: providerEntry?.provider, style: .compact) {
            if let providerEntry {
                CompactMetricView(entry: providerEntry, metric: self.entry.metric)
            } else {
                self.emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Open CodexBar")
                .font(.body)
                .fontWeight(.semibold)
            Text("Usage data will appear once the app refreshes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}

struct CodexBarSwitcherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodexBarSwitcherEntry

    var body: some View {
        let providerEntry = self.entry.snapshot.entries.first { $0.provider == self.entry.provider }
        WidgetSurface(provider: providerEntry?.provider, style: .switcher) {
            VStack(alignment: .leading, spacing: 10) {
                ProviderSwitcherRow(
                    providers: self.entry.availableProviders,
                    selected: self.entry.provider,
                    updatedAt: providerEntry?.updatedAt ?? Date(),
                    compact: self.family == .systemSmall,
                    showsTimestamp: self.family != .systemSmall)
                if let providerEntry {
                    self.content(providerEntry: providerEntry)
                } else {
                    self.emptyState
                }
            }
        }
    }

    @ViewBuilder
    private func content(providerEntry: WidgetSnapshot.ProviderEntry) -> some View {
        switch self.family {
        case .systemSmall:
            SwitcherSmallUsageView(entry: providerEntry, showUsed: self.entry.snapshot.usageBarsShowUsed)
        case .systemMedium:
            SwitcherMediumUsageView(entry: providerEntry, showUsed: self.entry.snapshot.usageBarsShowUsed)
        default:
            SwitcherLargeUsageView(entry: providerEntry, showUsed: self.entry.snapshot.usageBarsShowUsed)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Open CodexBar")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Usage data appears after a refresh.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CompactMetricView: View {
    let entry: WidgetSnapshot.ProviderEntry
    let metric: CompactMetric

    var body: some View {
        let display = self.display
        VStack(alignment: .leading, spacing: 8) {
            HeaderView(provider: self.entry.provider, updatedAt: self.entry.updatedAt)
            VStack(alignment: .leading, spacing: 2) {
                Text(display.value)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(display.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let detail = display.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
    }

    private var display: (value: String, label: String, detail: String?) {
        switch self.metric {
        case .credits:
            let value = self.entry.creditsRemaining.map(WidgetFormat.credits) ?? "—"
            return (value, "Credits left", nil)
        case .todayCost:
            let value = self.entry.tokenUsage?.sessionCostUSD.map(WidgetFormat.usd) ?? "—"
            let detail = self.entry.tokenUsage?.sessionTokens.map(WidgetFormat.tokenCount)
            return (value, "Today cost", detail)
        case .last30DaysCost:
            let value = self.entry.tokenUsage?.last30DaysCostUSD.map(WidgetFormat.usd) ?? "—"
            let detail = self.entry.tokenUsage?.last30DaysTokens.map(WidgetFormat.tokenCount)
            return (value, "30d cost", detail)
        }
    }
}

private struct ProviderSwitcherRow: View {
    let providers: [UsageProvider]
    let selected: UsageProvider
    let updatedAt: Date
    let compact: Bool
    let showsTimestamp: Bool

    var body: some View {
        HStack(spacing: self.compact ? 4 : 6) {
            ForEach(self.providers, id: \.self) { provider in
                if let url = self.selectionURL(for: provider) {
                    Link(destination: url) {
                        ProviderSwitchChip(
                            provider: provider,
                            selected: provider == self.selected,
                            compact: self.compact)
                    }
                    .buttonStyle(.plain)
                } else {
                    ProviderSwitchChip(
                        provider: provider,
                        selected: provider == self.selected,
                        compact: self.compact)
                }
            }
            if self.showsTimestamp {
                Spacer(minLength: 6)
                Text(WidgetFormat.relativeDate(self.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func selectionURL(for provider: UsageProvider) -> URL? {
        var components = URLComponents()
        components.scheme = "codexbar"
        components.host = "widget"
        components.path = "/select"
        components.queryItems = [URLQueryItem(name: "provider", value: provider.rawValue)]
        return components.url
    }
}

private struct ProviderSwitchChip: View {
    let provider: UsageProvider
    let selected: Bool
    let compact: Bool

    var body: some View {
        let label = self.compact ? self.shortLabel : self.longLabel
        let palette = WidgetColors.color(for: self.provider)
        let borderOpacity = self.selected ? 0.72 : 0.22
        let labelColor = self.selected ? Color.primary : Color.secondary

        Text(label)
            .font(self.compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .foregroundStyle(labelColor)
            .padding(.horizontal, self.compact ? 6 : 8)
            .padding(.vertical, self.compact ? 3 : 4)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(self.selected ? 0.28 : 0.12),
                                .clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom)
                            .opacity(self.selected ? 0.9 : 0.55))
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [palette.opacity(self.selected ? 1.0 : 0.5), palette.opacity(0.08)],
                                    startPoint: .top,
                                    endPoint: .bottom),
                                lineWidth: self.selected ? 1.25 : 0.8)))
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .opacity(self.selected ? 0.35 : 0.12)
            )
            .overlay {
                if self.selected {
                    Capsule()
                        .stroke(
                            palette.opacity(borderOpacity),
                            lineWidth: 1.3)
                        .blur(radius: 0.2)
                        .allowsHitTesting(false)
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [palette.opacity(0.35), .clear],
                                startPoint: .top,
                                endPoint: .bottom))
                        .frame(height: 2.6)
                        .mask(
                            Capsule()
                                .padding(.horizontal, 3.5)
                        )
                        .padding(.horizontal, 2.5)
                        .padding(.top, 2)
                        .offset(y: 0.6)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Capsule())
            .overlay(alignment: .center) {
                if self.selected {
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [palette.opacity(0.55), palette.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing),
                            lineWidth: 0.7)
                        .padding(0.4)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(Capsule())
            .compositingGroup()
    }

    private var longLabel: String {
        ProviderDefaults.metadata[self.provider]?.displayName ?? self.provider.rawValue.capitalized
    }

    private var shortLabel: String {
        switch self.provider {
        case .codex: "Codex"
        case .claude: "Claude"
        default: ProviderDefaults.metadata[self.provider]?.displayName ?? self.provider.rawValue.capitalized
        }
    }
}

private func displayedPercent(window: RateWindow?, showUsed: Bool) -> Double? {
    guard let window else { return nil }
    return showUsed ? window.usedPercent : window.remainingPercent
}

private func displayedCodeReviewPercent(remainingPercent: Double?, showUsed: Bool) -> Double? {
    guard let remainingPercent else { return nil }
    return showUsed ? max(0, min(100, 100 - remainingPercent)) : remainingPercent
}

private struct SwitcherSmallUsageView: View {
    let entry: WidgetSnapshot.ProviderEntry
    let showUsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UsageBarRow(
                title: ProviderDefaults.metadata[self.entry.provider]?.sessionLabel ?? "Session",
                percent: displayedPercent(window: self.entry.primary, showUsed: self.showUsed),
                color: WidgetColors.color(for: self.entry.provider))
            UsageBarRow(
                title: ProviderDefaults.metadata[self.entry.provider]?.weeklyLabel ?? "Weekly",
                percent: displayedPercent(window: self.entry.secondary, showUsed: self.showUsed),
                color: WidgetColors.color(for: self.entry.provider))
            if let codeReview = entry.codeReviewRemainingPercent {
                UsageBarRow(
                    title: "Code review",
                    percent: displayedCodeReviewPercent(remainingPercent: codeReview, showUsed: self.showUsed),
                    color: WidgetColors.color(for: self.entry.provider))
            }
        }
    }
}

private struct SwitcherMediumUsageView: View {
    let entry: WidgetSnapshot.ProviderEntry
    let showUsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            UsageBarRow(
                title: ProviderDefaults.metadata[self.entry.provider]?.sessionLabel ?? "Session",
                percent: displayedPercent(window: self.entry.primary, showUsed: self.showUsed),
                color: WidgetColors.color(for: self.entry.provider))
            UsageBarRow(
                title: ProviderDefaults.metadata[self.entry.provider]?.weeklyLabel ?? "Weekly",
                percent: displayedPercent(window: self.entry.secondary, showUsed: self.showUsed),
                color: WidgetColors.color(for: self.entry.provider))
            if let credits = entry.creditsRemaining {
                ValueLine(title: "Credits", value: WidgetFormat.credits(credits))
            }
            if let token = entry.tokenUsage {
                ValueLine(
                    title: "Today",
                    value: WidgetFormat.costAndTokens(cost: token.sessionCostUSD, tokens: token.sessionTokens))
            }
        }
    }
}

private struct SwitcherLargeUsageView: View {
    let entry: WidgetSnapshot.ProviderEntry
    let showUsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            UsageBarRow(
                title: ProviderDefaults.metadata[self.entry.provider]?.sessionLabel ?? "Session",
                percent: displayedPercent(window: self.entry.primary, showUsed: self.showUsed),
                color: WidgetColors.color(for: self.entry.provider))
            UsageBarRow(
                title: ProviderDefaults.metadata[self.entry.provider]?.weeklyLabel ?? "Weekly",
                percent: displayedPercent(window: self.entry.secondary, showUsed: self.showUsed),
                color: WidgetColors.color(for: self.entry.provider))
            if let codeReview = entry.codeReviewRemainingPercent {
                UsageBarRow(
                    title: "Code review",
                    percent: displayedCodeReviewPercent(remainingPercent: codeReview, showUsed: self.showUsed),
                    color: WidgetColors.color(for: self.entry.provider))
            }
            if let credits = entry.creditsRemaining {
                ValueLine(title: "Credits", value: WidgetFormat.credits(credits))
            }
            if let token = entry.tokenUsage {
                VStack(alignment: .leading, spacing: 4) {
                    ValueLine(
                        title: "Today",
                        value: WidgetFormat.costAndTokens(cost: token.sessionCostUSD, tokens: token.sessionTokens))
                    ValueLine(
                        title: "30d",
                        value: WidgetFormat.costAndTokens(
                            cost: token.last30DaysCostUSD,
                            tokens: token.last30DaysTokens))
                }
            }
            UsageHistoryChart(points: self.entry.dailyUsage, color: WidgetColors.color(for: self.entry.provider))
                .frame(height: 50)
        }
    }
}

private struct SmallUsageView: View {
    let entry: WidgetSnapshot.ProviderEntry
    let showUsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderView(
                provider: self.entry.provider,
                updatedAt: self.entry.updatedAt,
                sessionPercent: displayedPercent(window: self.entry.primary, showUsed: self.showUsed),
                weeklyPercent: displayedPercent(window: self.entry.secondary, showUsed: self.showUsed))
            UsageBarRow(
                title: ProviderDefaults.metadata[self.entry.provider]?.sessionLabel ?? "Session",
                percent: displayedPercent(window: self.entry.primary, showUsed: self.showUsed),
                color: WidgetColors.color(for: self.entry.provider))
            UsageBarRow(
                title: ProviderDefaults.metadata[self.entry.provider]?.weeklyLabel ?? "Weekly",
                percent: displayedPercent(window: self.entry.secondary, showUsed: self.showUsed),
                color: WidgetColors.color(for: self.entry.provider))
            if let codeReview = entry.codeReviewRemainingPercent {
                UsageBarRow(
                    title: "Code review",
                    percent: displayedCodeReviewPercent(remainingPercent: codeReview, showUsed: self.showUsed),
                    color: WidgetColors.color(for: self.entry.provider))
            }
        }
    }
}

private struct MediumUsageView: View {
    let entry: WidgetSnapshot.ProviderEntry
    let showUsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HeaderView(
                provider: self.entry.provider,
                updatedAt: self.entry.updatedAt,
                sessionPercent: displayedPercent(window: self.entry.primary, showUsed: self.showUsed),
                weeklyPercent: displayedPercent(window: self.entry.secondary, showUsed: self.showUsed))
            UsageBarRow(
                title: ProviderDefaults.metadata[self.entry.provider]?.sessionLabel ?? "Session",
                percent: displayedPercent(window: self.entry.primary, showUsed: self.showUsed),
                color: WidgetColors.color(for: self.entry.provider))
            UsageBarRow(
                title: ProviderDefaults.metadata[self.entry.provider]?.weeklyLabel ?? "Weekly",
                percent: displayedPercent(window: self.entry.secondary, showUsed: self.showUsed),
                color: WidgetColors.color(for: self.entry.provider))
            if let credits = entry.creditsRemaining {
                ValueLine(title: "Credits", value: WidgetFormat.credits(credits))
            }
            if let token = entry.tokenUsage {
                ValueLine(
                    title: "Today",
                    value: WidgetFormat.costAndTokens(cost: token.sessionCostUSD, tokens: token.sessionTokens))
            }
        }
    }
}

private struct LargeUsageView: View {
    let entry: WidgetSnapshot.ProviderEntry
    let showUsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderView(
                provider: self.entry.provider,
                updatedAt: self.entry.updatedAt,
                sessionPercent: displayedPercent(window: self.entry.primary, showUsed: self.showUsed),
                weeklyPercent: displayedPercent(window: self.entry.secondary, showUsed: self.showUsed))
            UsageBarRow(
                title: ProviderDefaults.metadata[self.entry.provider]?.sessionLabel ?? "Session",
                percent: displayedPercent(window: self.entry.primary, showUsed: self.showUsed),
                color: WidgetColors.color(for: self.entry.provider))
            UsageBarRow(
                title: ProviderDefaults.metadata[self.entry.provider]?.weeklyLabel ?? "Weekly",
                percent: displayedPercent(window: self.entry.secondary, showUsed: self.showUsed),
                color: WidgetColors.color(for: self.entry.provider))
            if let codeReview = entry.codeReviewRemainingPercent {
                UsageBarRow(
                    title: "Code review",
                    percent: displayedCodeReviewPercent(remainingPercent: codeReview, showUsed: self.showUsed),
                    color: WidgetColors.color(for: self.entry.provider))
            }
            if let credits = entry.creditsRemaining {
                ValueLine(title: "Credits", value: WidgetFormat.credits(credits))
            }
            if let token = entry.tokenUsage {
                VStack(alignment: .leading, spacing: 4) {
                    ValueLine(
                        title: "Today",
                        value: WidgetFormat.costAndTokens(cost: token.sessionCostUSD, tokens: token.sessionTokens))
                    ValueLine(
                        title: "30d",
                        value: WidgetFormat.costAndTokens(
                            cost: token.last30DaysCostUSD,
                            tokens: token.last30DaysTokens))
                }
            }
            UsageHistoryChart(points: self.entry.dailyUsage, color: WidgetColors.color(for: self.entry.provider))
                .frame(height: 50)
        }
    }
}

private struct HistoryView: View {
    let entry: WidgetSnapshot.ProviderEntry
    let isLarge: Bool
    let showUsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderView(
                provider: self.entry.provider,
                updatedAt: self.entry.updatedAt,
                sessionPercent: displayedPercent(window: self.entry.primary, showUsed: self.showUsed),
                weeklyPercent: displayedPercent(window: self.entry.secondary, showUsed: self.showUsed))
            UsageHistoryChart(points: self.entry.dailyUsage, color: WidgetColors.color(for: self.entry.provider))
                .frame(height: self.isLarge ? 90 : 60)
            if let token = entry.tokenUsage {
                ValueLine(
                    title: "Today",
                    value: WidgetFormat.costAndTokens(cost: token.sessionCostUSD, tokens: token.sessionTokens))
                ValueLine(
                    title: "30d",
                    value: WidgetFormat.costAndTokens(cost: token.last30DaysCostUSD, tokens: token.last30DaysTokens))
            }
        }
    }
}

private struct HeaderView: View {
    let provider: UsageProvider
    let updatedAt: Date
    let sessionPercent: Double?
    let weeklyPercent: Double?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            CodexBarMeterGlyph(
                sessionPercent: self.sessionPercent,
                weeklyPercent: self.weeklyPercent,
                color: WidgetColors.color(for: self.provider))
            GlassSurfaceLabel(
                text: ProviderDefaults.metadata[self.provider]?.displayName ?? self.provider.rawValue.capitalized,
                accent: WidgetColors.color(for: self.provider))
            Spacer()
            Text(WidgetFormat.relativeDate(self.updatedAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CompactMetricTitle: View {
    let text: String

    var body: some View {
        Text(self.text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private extension HeaderView {
    init(provider: UsageProvider, updatedAt: Date) {
        self.init(provider: provider, updatedAt: updatedAt, sessionPercent: nil, weeklyPercent: nil)
    }
}

private struct CodexBarMeterGlyph: View {
    let sessionPercent: Double?
    let weeklyPercent: Double?
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            MeterStripe(fillPercent: self.sessionPercent, color: self.color, height: 5)
            MeterStripe(fillPercent: self.weeklyPercent, color: self.color.opacity(0.85), height: 3)
        }
        .frame(width: 18, height: 12)
        .accessibilityHidden(true)
    }
}

private struct MeterStripe: View {
    let fillPercent: Double?
    let color: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = max(0, min(1, (self.fillPercent ?? 0) / 100)) * proxy.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: self.height / 2, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: self.height / 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [self.color.opacity(0.62), self.color.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom))
                    .frame(width: width)
                if let fillPercent, fillPercent < 100 {
                    RoundedRectangle(cornerRadius: self.height / 2, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: max(0, width - 4))
                        .padding(.leading, 2)
                }
            }
        }
        .frame(height: self.height)
    }
}

private struct UsageBarRow: View {
    let title: String
    let percent: Double?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(self.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                GlassMetricPill(
                    text: WidgetFormat.percent(self.percent),
                    color: self.color,
                    emphasized: true)
            }
            GeometryReader { proxy in
                let ratio = max(0, min(1, (self.percent ?? 0) / 100))
                let width = ratio * proxy.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.72))
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    self.color.opacity(0.60),
                                    self.color.opacity(0.95),
                                ],
                                startPoint: .top,
                                endPoint: .bottom))
                        .frame(width: width)
                    if let percent, percent < 100 {
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(self.color.opacity(0.22))
                            .frame(width: max(0, width - 7))
                            .padding(.leading, 4)
                    }
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(Color.white.opacity(0.22))
                        .frame(width: width)
                        .blendMode(.screen)
                        .mask(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .frame(width: width)
                        )
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 7)
        }
    }
}

private struct ValueLine: View {
    let title: String
    let value: String
    var body: some View {
        HStack(spacing: 6) {
            Text(self.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(.thinMaterial.opacity(0.5))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.6)))
                .compositingGroup()
            Spacer(minLength: 0)
            Text(self.value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .padding(.trailing, 1)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
    }
}

private struct UsageHistoryChart: View {
    let points: [WidgetSnapshot.DailyUsagePoint]
    let color: Color

    var body: some View {
        let values = self.points.map { point -> Double in
            if let cost = point.costUSD { return cost }
            return Double(point.totalTokens ?? 0)
        }
        let maxValue = values.max() ?? 0
        let barColor = self.color
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(values.indices, id: \.self) { index in
                let value = values[index]
                let height = maxValue > 0 ? CGFloat(value / maxValue) : 0
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [barColor.opacity(0.45), barColor.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom))
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: 1, y: height, anchor: .bottom)
            }
        }
        .padding(4)
        .background(
            LiquidGlassChartBackground()
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(barColor.opacity(0.28), lineWidth: 0.45)
                .blendMode(.screen)
                .allowsHitTesting(false))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .trim(from: 0, to: 0.98)
                    .stroke(barColor.opacity(0.24), lineWidth: 0.4)
                    .padding(0.6)
                    .allowsHitTesting(false))
    }
}

enum WidgetColors {
    // swiftlint:disable:next cyclomatic_complexity
    static func color(for provider: UsageProvider) -> Color {
        switch provider {
        case .codex:
            Color(red: 73 / 255, green: 163 / 255, blue: 176 / 255)
        case .claude:
            Color(red: 204 / 255, green: 124 / 255, blue: 94 / 255)
        case .gemini:
            Color(red: 171 / 255, green: 135 / 255, blue: 234 / 255)
        case .antigravity:
            Color(red: 96 / 255, green: 186 / 255, blue: 126 / 255)
        case .cursor:
            Color(red: 0 / 255, green: 191 / 255, blue: 165 / 255) // #00BFA5 - Cursor teal
        case .opencode:
            Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
        case .zai:
            Color(red: 232 / 255, green: 90 / 255, blue: 106 / 255)
        case .factory:
            Color(red: 255 / 255, green: 107 / 255, blue: 53 / 255) // Factory orange
        case .copilot:
            Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255) // Purple
        case .minimax:
            Color(red: 254 / 255, green: 96 / 255, blue: 60 / 255)
        case .vertexai:
            Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255) // Google Blue
        case .kiro:
            Color(red: 255 / 255, green: 153 / 255, blue: 0 / 255) // AWS orange
        case .augment:
            Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255) // Augment purple
        case .jetbrains:
            Color(red: 255 / 255, green: 51 / 255, blue: 153 / 255) // JetBrains pink
        case .kimi:
            Color(red: 254 / 255, green: 96 / 255, blue: 60 / 255) // Kimi orange
        case .kimik2:
            Color(red: 76 / 255, green: 0 / 255, blue: 255 / 255) // Kimi K2 purple
        case .amp:
            Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255) // Amp red
        case .ollama:
            Color(red: 32 / 255, green: 32 / 255, blue: 32 / 255) // Ollama charcoal
        case .synthetic:
            Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255) // Synthetic charcoal
        case .openrouter:
            Color(red: 111 / 255, green: 66 / 255, blue: 193 / 255) // OpenRouter purple
        case .warp:
            Color(red: 147 / 255, green: 139 / 255, blue: 180 / 255)
        }
    }
}

enum WidgetFormat {
    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", value)
    }

    static func credits(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    static func costAndTokens(cost: Double?, tokens: Int?) -> String {
        let costText = cost.map(self.usd) ?? "—"
        if let tokens {
            return "\(costText) · \(self.tokenCount(tokens))"
        }
        return costText
    }

    static func usd(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    static func tokenCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let raw = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(raw) tokens"
    }

    static func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
