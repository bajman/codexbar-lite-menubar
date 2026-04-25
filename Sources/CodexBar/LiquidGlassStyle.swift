import CodexBarCore
import SwiftUI

// MARK: - Centralized 8pt-grid spacing constants for the menu panel

enum MenuPanelMetrics {
    // MARK: - Outer Shell (NSGlassEffectView)

    static let shellCornerRadius: CGFloat = 16
    static let shellHorizontalPadding: CGFloat = 12
    static let shellTopPadding: CGFloat = 12
    static let shellBottomPadding: CGFloat = 12
    static let panelAttachmentGap: CGFloat = 12
    static let screenEdgeInset: CGFloat = 12

    // MARK: - Inner Surfaces

    static let cardCornerRadius: CGFloat = 14
    static let sectionCornerRadius: CGFloat = 14
    static let contentHorizontalPadding: CGFloat = 18
    static let cardTopPadding: CGFloat = 16
    static let cardBottomPadding: CGFloat = 16
    static let compactSurfacePadding: CGFloat = 10
    static let chartSurfacePadding: CGFloat = 14
    static let footerBottomPadding: CGFloat = shellBottomPadding

    // MARK: - Section Spacing

    static let compactSpacing: CGFloat = 6
    static let sectionSpacing: CGFloat = 10
    static let chartSectionSpacing: CGFloat = 14
    static let metricRowSpacing: CGFloat = 10
    static let headerSpacing: CGFloat = 6
    static let inlineSpacing: CGFloat = 10

    // MARK: - Chart Disclosure

    static let disclosureHorizontalPadding: CGFloat = 16
    static let disclosureVerticalPadding: CGFloat = 10

    // MARK: - Action Buttons

    static let actionIconWidth: CGFloat = 24
    static let actionHorizontalPadding: CGFloat = contentHorizontalPadding
    static let actionVerticalPadding: CGFloat = 10
    static let chipHorizontalPadding: CGFloat = 8
    static let chipVerticalPadding: CGFloat = 4

    // MARK: - Progress Bar

    static let progressBarHeight: CGFloat = 8

    static func contentWidth(for shellWidth: CGFloat) -> CGFloat {
        shellWidth - (self.shellHorizontalPadding * 2)
    }
}

// MARK: - Glass Background Modifier

struct MenuGlassBackground: ViewModifier {
    @Environment(\.liquidGlassActive) private var isActive

    let layer: LiquidGlassLayer
    let cornerRadius: CGFloat
    /// When true, skip the SwiftUI `.glassEffect()` call — the glass is
    /// provided at the AppKit level (e.g. via `NSGlassEffectView`).
    let skipGlassEffect: Bool

    @State private var flashOpacity: Double = 0

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
        let useSwiftUIGlass = self.isActive
            && LiquidGlassAvailability.shouldApplyGlass
            && !self.skipGlassEffect

        if self.layer == .none {
            content
        } else if useSwiftUIGlass {
            if #available(macOS 26.4, *) {
                content.background {
                    shape
                        .fill(.clear)
                        .glassEffect(.regular, in: shape)
                        .overlay {
                            self.luminousEdge(shape: shape)
                        }
                }
                .overlay {
                    shape.fill(Color.white.opacity(self.flashOpacity))
                        .allowsHitTesting(false)
                }
                .onChange(of: self.isActive) {
                    self.flashOpacity = 0.35
                    withAnimation(.easeOut(duration: 0.4)) {
                        self.flashOpacity = 0
                    }
                }
            } else {
                content.background(self.materialStyle, in: shape)
            }
        } else if self.isActive, LiquidGlassAvailability.shouldApplyGlass {
            // Glass effect is handled externally (e.g. NSGlassEffectView);
            // pass content through without adding a background.
            content
        } else {
            content
                .background(self.materialStyle, in: shape)
                .overlay {
                    shape.fill(Color.white.opacity(self.flashOpacity))
                        .allowsHitTesting(false)
                }
                .onChange(of: self.isActive) {
                    self.flashOpacity = 0.35
                    withAnimation(.easeOut(duration: 0.4)) {
                        self.flashOpacity = 0
                    }
                }
        }
    }

    private var materialStyle: Material {
        switch self.layer {
        case .shell:
            .thickMaterial
        case .card:
            .regularMaterial
        case .pill:
            .ultraThinMaterial
        case .none:
            .regularMaterial
        }
    }

    private var luminousEdgeGradient: AngularGradient {
        let topLeft = Color.white.opacity(0.72)
        let bottomRight = Color.accentColor.opacity(0.32)
        return AngularGradient(
            gradient: Gradient(stops: [
                .init(color: topLeft, location: 0.0),
                .init(color: .clear, location: 0.24),
                .init(color: .clear, location: 0.34),
                .init(color: bottomRight, location: 0.50),
                .init(color: bottomRight, location: 0.62),
                .init(color: .clear, location: 0.72),
                .init(color: topLeft, location: 0.96),
                .init(color: topLeft, location: 1.0),
            ]),
            center: .center,
            angle: .degrees(-135))
    }

    private func luminousEdge(shape: RoundedRectangle) -> some View {
        shape
            .inset(by: 0.25)
            .stroke(self.luminousEdgeGradient, lineWidth: 0.5)
    }
}

enum MenuContentSurfaceProminence {
    case regular
    case subtle
}

private struct MenuContentSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.liquidGlassActive) private var isGlassActive
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let cornerRadius: CGFloat
    let prominence: MenuContentSurfaceProminence

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
        content
            .background(self.fillColor, in: shape)
            .overlay {
                shape.strokeBorder(self.strokeColor, lineWidth: self.strokeWidth)
            }
            .shadow(
                color: self.shadowColor,
                radius: self.shadowRadius,
                x: 0,
                y: self.shadowYOffset)
    }

    private var fillColor: Color {
        if self.reduceTransparency {
            return Color(nsColor: .controlBackgroundColor)
        }

        let base = Color(nsColor: .controlBackgroundColor)
        if self.isGlassActive {
            switch (self.prominence, self.colorScheme) {
            case (.regular, .dark):
                return base.opacity(0.56)
            case (.regular, .light):
                return base.opacity(0.40)
            case (.subtle, .dark):
                return base.opacity(0.42)
            case (.subtle, .light):
                return base.opacity(0.28)
            @unknown default:
                return base.opacity(0.40)
            }
        }

        return base.opacity(self.prominence == .regular ? 0.90 : 0.76)
    }

    private var strokeColor: Color {
        if self.reduceTransparency {
            return Color(nsColor: .separatorColor).opacity(0.55)
        }
        return Color(nsColor: .separatorColor).opacity(self.isGlassActive ? 0.30 : 0.18)
    }

    private var strokeWidth: CGFloat {
        self.reduceTransparency ? 1 : 0.8
    }

    private var shadowColor: Color {
        guard self.isGlassActive, !self.reduceTransparency else { return .clear }
        return Color.black.opacity(self.prominence == .regular ? 0.08 : 0.05)
    }

    private var shadowRadius: CGFloat {
        self.prominence == .regular ? 18 : 12
    }

    private var shadowYOffset: CGFloat {
        self.prominence == .regular ? 10 : 6
    }
}

extension View {
    func menuGlassBackground(
        layer: LiquidGlassLayer = .shell,
        cornerRadius: CGFloat = 10,
        skipGlassEffect: Bool = false) -> some View
    {
        modifier(MenuGlassBackground(
            layer: layer,
            cornerRadius: cornerRadius,
            skipGlassEffect: skipGlassEffect))
    }

    func menuContentSurface(
        cornerRadius: CGFloat = MenuPanelMetrics.cardCornerRadius,
        prominence: MenuContentSurfaceProminence = .regular) -> some View
    {
        modifier(MenuContentSurface(cornerRadius: cornerRadius, prominence: prominence))
    }
}
