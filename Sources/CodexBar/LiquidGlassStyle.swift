import CodexBarCore
import SwiftUI

struct MenuGlassBackground: ViewModifier {
    let layer: LiquidGlassLayer
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if LiquidGlassAvailability.shouldApplyGlass, layer != .none {
            if #available(macOS 26, *) {
                content.background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular.interactive(),
                                     in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            } else { content }
        } else { content }
    }
}

extension View {
    func menuGlassBackground(layer: LiquidGlassLayer = .shell, cornerRadius: CGFloat = 10) -> some View {
        modifier(MenuGlassBackground(layer: layer, cornerRadius: cornerRadius))
    }
}
