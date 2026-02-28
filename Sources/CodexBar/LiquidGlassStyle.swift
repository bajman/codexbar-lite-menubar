import CodexBarCore
import SwiftUI

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
                        .glassEffect(.clear.interactive(), in: shape)
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
        let topLeft = Color.white.opacity(0.8)
        let bottomRight = Color(red: 0.57, green: 0.44, blue: 0.98).opacity(0.5)
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
}
