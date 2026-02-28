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

    private var segments: [Segment] {
        var result: [Segment] = []
        if self.includesOverview {
            result.append(Segment(
                selection: .overview,
                title: "Overview",
                icon: .system("square.grid.2x2"),
                weeklyRemaining: nil))
        }
        for provider in self.providers {
            let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
            let nsImage = self.iconProvider(provider)
            nsImage.isTemplate = true
            nsImage.size = NSSize(width: 16, height: 16)
            result.append(Segment(
                selection: .provider(provider),
                title: descriptor.metadata.displayName,
                icon: .nsImage(nsImage),
                weeklyRemaining: self.weeklyRemainingProvider(provider)))
        }
        return result
    }

    var body: some View {
        let allSegments = self.segments
        VStack(spacing: 4) {
            Picker("Provider", selection: Binding(
                get: { self.selected ?? allSegments.first?.selection ?? .provider(.codex) },
                set: { self.onSelect($0) }))
            {
                ForEach(allSegments, id: \.selection) { segment in
                    if self.showsIcons {
                        Label {
                            Text(segment.shortTitle)
                        } icon: {
                            self.segmentIcon(segment.icon)
                        }
                        .tag(segment.selection)
                    } else {
                        Text(segment.shortTitle)
                            .tag(segment.selection)
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            if case let .provider(provider) = (self.selected ?? allSegments.first?.selection),
               let weeklyRemaining = self.weeklyRemainingProvider(provider)
            {
                HStack {
                    Text("Weekly")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f%% left", max(0, min(100, weeklyRemaining))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func segmentIcon(_ icon: SegmentIcon) -> some View {
        switch icon {
        case let .system(name):
            return AnyView(
                Image(systemName: name)
                    .imageScale(.small))
        case let .nsImage(image):
            return AnyView(
                Image(nsImage: image)
                    .renderingMode(.template))
        }
    }

}

// MARK: - GlassTokenAccountSwitcherView

struct GlassTokenAccountSwitcherView: View {
    let accounts: [ProviderTokenAccount]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    @State private var hoveredIndex: Int?

    private var useGrid: Bool {
        self.accounts.count > 3
    }

    var body: some View {
        if self.useGrid {
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: 4),
                count: Int(ceil(Double(accounts.count) / 2.0)))
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(self.accounts.enumerated()), id: \.offset) { index, account in
                    self.accountButton(index: index, account: account)
                }
            }
            .padding(.horizontal, 6)
        } else {
            HStack(spacing: 4) {
                ForEach(Array(self.accounts.enumerated()), id: \.offset) { index, account in
                    self.accountButton(index: index, account: account)
                }
            }
            .padding(.horizontal, 6)
        }
    }

    private func accountButton(index: Int, account: ProviderTokenAccount) -> some View {
        let isSelected = index == self.selectedIndex
        let isHovered = self.hoveredIndex == index

        return Button {
            self.onSelect(index)
        } label: {
            Text(account.displayName)
                .font(.system(size: NSFont.smallSystemFontSize))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
        }
        .glassSegmentStyle(isSelected: isSelected, isHovered: isHovered)
        .onHover { hovering in
            self.hoveredIndex = hovering ? index : nil
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

    var shortTitle: String {
        if self.selection == .overview {
            return "All"
        }
        return self.title
    }
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
            .foregroundStyle(self.isSelected ? Color.white : Color.secondary)
            .background(self.backgroundFill)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var backgroundFill: some ShapeStyle {
        if self.isSelected {
            AnyShapeStyle(Color.accentColor)
        } else if self.isHovered {
            AnyShapeStyle(Color.primary.opacity(0.08))
        } else {
            AnyShapeStyle(Color.clear)
        }
    }
}

extension View {
    @ViewBuilder
    fileprivate func glassSegmentStyle(isSelected: Bool, isHovered: Bool) -> some View {
        if #available(macOS 26, *), LiquidGlassAvailability.shouldApplyGlass {
            buttonStyle(.glass)
                .tint(isSelected ? Color.accentColor : nil)
        } else {
            buttonStyle(GlassSegmentButtonStyle(
                isSelected: isSelected,
                isHovered: isHovered))
        }
    }
}
