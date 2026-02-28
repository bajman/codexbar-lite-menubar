import CodexBarCore
import SwiftUI

struct UsageProgressBar: View {
    let percent: Double
    let tint: Color
    let accessibilityLabel: String
    let pacePercent: Double?
    let paceOnTop: Bool

    @Environment(\.menuItemHighlighted) private var isHighlighted

    init(
        percent: Double,
        tint: Color,
        accessibilityLabel: String,
        pacePercent: Double? = nil,
        paceOnTop: Bool = true)
    {
        self.percent = percent
        self.tint = tint
        self.accessibilityLabel = accessibilityLabel
        self.pacePercent = pacePercent
        self.paceOnTop = paceOnTop
    }

    private var clamped: Double {
        min(100, max(0, self.percent))
    }

    private var paceMarkerTint: Color {
        if self.isHighlighted {
            return MenuHighlightStyle.selectionText
        }
        return self.paceOnTop ? .secondary : Color(nsColor: .systemRed)
    }

    private var resolvedProgressTint: Color {
        MenuHighlightStyle.progressTint(self.isHighlighted, fallback: self.tint)
    }

    var body: some View {
        GeometryReader { proxy in
            let markerWidth: CGFloat = 2
            let paceX = proxy.size.width * Self.clampedPercent(self.pacePercent) / 100
            let markerOffset = max(0, min(proxy.size.width - markerWidth, paceX - (markerWidth / 2)))
            ZStack(alignment: .leading) {
                ProgressView(value: self.clamped, total: 100)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .tint(self.resolvedProgressTint)

                if self.pacePercent != nil {
                    RoundedRectangle(cornerRadius: markerWidth / 2, style: .continuous)
                        .fill(self.paceMarkerTint)
                        .frame(width: markerWidth)
                        .offset(x: markerOffset)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 8)
        .accessibilityLabel(self.accessibilityLabel)
        .accessibilityValue("\(Int(self.clamped)) percent")
    }

    private static func clampedPercent(_ value: Double?) -> Double {
        guard let value else { return 0 }
        return min(100, max(0, value))
    }
}
