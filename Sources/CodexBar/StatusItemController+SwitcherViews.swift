import CodexBarCore
import SwiftUI

enum ProviderSwitcherSelection: Equatable {
    case overview
    case provider(UsageProvider)
}

// MARK: - GlassProviderSwitcherView

struct GlassProviderSwitcherView: View {
    let providers: [UsageProvider]
    let selected: ProviderSwitcherSelection?
    let includesOverview: Bool
    let showsIcons: Bool
    let iconProvider: (UsageProvider) -> NSImage
    let weeklyRemainingProvider: (UsageProvider) -> Double?
    let onSelect: (ProviderSwitcherSelection) -> Void

    @State private var hoveredSelection: ProviderSwitcherSelection?

    private var segments: [Segment] {
        var result: [Segment] = []
        if includesOverview {
            result.append(Segment(
                selection: .overview,
                title: "Overview",
                icon: .system("square.grid.2x2"),
                weeklyRemaining: nil,
                brandColor: nil))
        }
        for provider in providers {
            let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
            let nsImage = iconProvider(provider)
            nsImage.isTemplate = true
            nsImage.size = NSSize(width: 16, height: 16)
            let branding = descriptor.branding.color
            result.append(Segment(
                selection: .provider(provider),
                title: descriptor.metadata.displayName,
                icon: .nsImage(nsImage),
                weeklyRemaining: weeklyRemainingProvider(provider),
                brandColor: Color(
                    red: branding.red,
                    green: branding.green,
                    blue: branding.blue)))
        }
        return result
    }

    private var useGrid: Bool { segments.count > 3 }

    var body: some View {
        let allSegments = segments
        if useGrid {
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: 4),
                count: gridColumnCount(total: allSegments.count))
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(allSegments, id: \.selection) { segment in
                    segmentButton(segment, stacked: showsIcons)
                }
            }
            .padding(.horizontal, 6)
        } else {
            HStack(spacing: 4) {
                ForEach(allSegments, id: \.selection) { segment in
                    segmentButton(segment, stacked: false)
                }
            }
            .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private func segmentButton(_ segment: Segment, stacked: Bool) -> some View {
        let isSelected = selected == segment.selection
        let isHovered = hoveredSelection == segment.selection

        Button {
            onSelect(segment.selection)
        } label: {
            VStack(spacing: stacked ? 2 : 0) {
                if stacked {
                    stackedContent(segment)
                } else {
                    inlineContent(segment)
                }
                weeklyIndicator(segment: segment, isSelected: isSelected)
            }
        }
        .glassSegmentStyle(isSelected: isSelected, isHovered: isHovered)
        .onHover { hovering in
            hoveredSelection = hovering ? segment.selection : nil
        }
    }

    @ViewBuilder
    private func inlineContent(_ segment: Segment) -> some View {
        HStack(spacing: 4) {
            if showsIcons {
                segmentIcon(segment.icon)
                    .frame(width: 16, height: 16)
            }
            Text(segment.title)
                .font(.system(size: NSFont.smallSystemFontSize))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func stackedContent(_ segment: Segment) -> some View {
        VStack(spacing: 0) {
            segmentIcon(segment.icon)
                .frame(width: 16, height: 16)
            Text(segment.title)
                .font(.system(size: NSFont.smallSystemFontSize - 2))
                .lineLimit(segments.count > 8 ? 2 : 1)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func segmentIcon(_ icon: SegmentIcon) -> some View {
        switch icon {
        case let .system(name):
            Image(systemName: name)
                .imageScale(.small)
        case let .nsImage(image):
            Image(nsImage: image)
                .renderingMode(.template)
        }
    }

    @ViewBuilder
    private func weeklyIndicator(segment: Segment, isSelected: Bool) -> some View {
        if let remaining = segment.weeklyRemaining, !isSelected {
            let ratio = CGFloat(max(0, min(1, remaining / 100)))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.22))
                    Capsule()
                        .fill(segment.brandColor ?? Color.secondary)
                        .frame(width: geometry.size.width * ratio)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 6)
            .padding(.bottom, 1)
        } else {
            // Reserve space so layout doesn't shift when selecting.
            Color.clear
                .frame(height: 4)
                .padding(.horizontal, 6)
                .padding(.bottom, 1)
                .opacity(segment.weeklyRemaining != nil ? 0 : 0)
        }
    }

    private func gridColumnCount(total: Int) -> Int {
        if total <= 4 { return 2 }
        if total <= 6 { return 3 }
        if total <= 9 { return 3 }
        return 4
    }
}

// MARK: - GlassTokenAccountSwitcherView

struct GlassTokenAccountSwitcherView: View {
    let accounts: [ProviderTokenAccount]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    @State private var hoveredIndex: Int?

    private var useGrid: Bool { accounts.count > 3 }

    var body: some View {
        if useGrid {
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: 4),
                count: Int(ceil(Double(accounts.count) / 2.0)))
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(accounts.enumerated()), id: \.offset) { index, account in
                    accountButton(index: index, account: account)
                }
            }
            .padding(.horizontal, 6)
        } else {
            HStack(spacing: 4) {
                ForEach(Array(accounts.enumerated()), id: \.offset) { index, account in
                    accountButton(index: index, account: account)
                }
            }
            .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private func accountButton(index: Int, account: ProviderTokenAccount) -> some View {
        let isSelected = index == selectedIndex
        let isHovered = hoveredIndex == index

        Button {
            onSelect(index)
        } label: {
            Text(account.displayName)
                .font(.system(size: NSFont.smallSystemFontSize))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
        }
        .glassSegmentStyle(isSelected: isSelected, isHovered: isHovered)
        .onHover { hovering in
            hoveredIndex = hovering ? index : nil
        }
        .help(account.displayName)
    }
}

// MARK: - Private Types

private struct Segment {
    let selection: ProviderSwitcherSelection
    let title: String
    let icon: SegmentIcon
    let weeklyRemaining: Double?
    let brandColor: Color?
}

private enum SegmentIcon {
    case system(String)
    case nsImage(NSImage)
}

extension ProviderSwitcherSelection: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .overview:
            hasher.combine(0)
        case let .provider(p):
            hasher.combine(1)
            hasher.combine(p)
        }
    }
}

// MARK: - Glass Segment Button Style

private struct GlassSegmentButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .background(backgroundFill)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var backgroundFill: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor)
        } else if isHovered {
            return AnyShapeStyle(Color.primary.opacity(0.08))
        } else {
            return AnyShapeStyle(Color.clear)
        }
    }
}

private extension View {
    @ViewBuilder
    func glassSegmentStyle(isSelected: Bool, isHovered: Bool) -> some View {
        if #available(macOS 26, *), LiquidGlassAvailability.shouldApplyGlass {
            self.buttonStyle(.glass)
                .tint(isSelected ? Color.accentColor : nil)
        } else {
            self.buttonStyle(GlassSegmentButtonStyle(
                isSelected: isSelected,
                isHovered: isHovered))
        }
    }
}
