import SwiftUI

extension EnvironmentValues {
    @Entry var menuItemHighlighted: Bool = false
}

enum MenuHighlightStyle {
    static let selectionText = Color(nsColor: .selectedMenuItemTextColor)

    static func primary(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : .primary
    }

    static func secondary(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : .secondary
    }

    static func glassSecondary(_ highlighted: Bool) -> Color {
        if highlighted { return self.selectionText }
        return .secondary
    }

    static func error(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : Color(nsColor: .systemRed)
    }

    static func progressTrack(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText.opacity(0.22) : Color(nsColor: .tertiaryLabelColor).opacity(0.22)
    }

    static func progressTint(_ highlighted: Bool, fallback: Color) -> Color {
        highlighted ? self.selectionText : fallback
    }

    static func selectionBackground(_ highlighted: Bool) -> Color {
        highlighted ? Color(nsColor: .selectedContentBackgroundColor) : .clear
    }

    static var glassFontDesign: Font.Design {
        .rounded
    }
}
