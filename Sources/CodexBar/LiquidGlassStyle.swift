import CodexBarCore
import SwiftUI

struct MenuGlassBackground: ViewModifier {
    let layer: LiquidGlassLayer
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if LiquidGlassAvailability.shouldApplyGlass, self.layer != .none {
            if #available(macOS 26, *) {
                content.background {
                    RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                        .fill(.clear)
                        .glassEffect(
                            .regular.interactive(),
                            in: RoundedRectangle(
                                cornerRadius: self.cornerRadius, style: .continuous))
                }
            } else {
                content.background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous))
            }
        } else if self.layer != .none {
            content.background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous))
        } else {
            content
        }
    }
}

extension View {
    func menuGlassBackground(layer: LiquidGlassLayer = .shell, cornerRadius: CGFloat = 10) -> some View {
        modifier(MenuGlassBackground(layer: layer, cornerRadius: cornerRadius))
    }
}
