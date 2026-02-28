import CodexBarCore
import SwiftUI

struct MenuGlassBackground: ViewModifier {
    @Environment(\.liquidGlassActive) private var isActive

    let layer: LiquidGlassLayer
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)

        if self.layer == .none {
            content
        } else if self.isActive && LiquidGlassAvailability.shouldApplyGlass {
            if #available(macOS 26.4, *) {
                content.background {
                    shape
                        .fill(.clear)
                        .glassEffect(.regular.interactive(), in: shape)
                        .overlay {
                            self.luminousEdge(shape: shape)
                        }
                }
            } else {
                content.background(self.materialStyle, in: shape)
            }
        } else {
            content.background(self.materialStyle, in: shape)
        }
    }

    private var materialStyle: Material {
        switch self.layer {
        case .shell:
            return .thickMaterial
        case .card:
            return .regularMaterial
        case .pill:
            return .ultraThinMaterial
        case .none:
            return .regularMaterial
        }
    }

    private var luminousEdgeGradient: AngularGradient {
        let topLeft = Color.white.opacity(0.2)
        let bottomRight = Color(red: 0.57, green: 0.44, blue: 0.98).opacity(0.1)
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
    func menuGlassBackground(layer: LiquidGlassLayer = .shell, cornerRadius: CGFloat = 10) -> some View {
        modifier(MenuGlassBackground(layer: layer, cornerRadius: cornerRadius))
    }
}
