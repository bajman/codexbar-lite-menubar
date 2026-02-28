import Foundation

#if canImport(AppKit)
import AppKit
#endif

public enum LiquidGlassLayer: String, Codable, Sendable {
    case shell, card, pill, none
}

public enum LiquidGlassAvailability: Sendable {
    public static func isGlassEnabled(
        defaults: UserDefaults? = .standard
    ) -> Bool {
        guard let defaults else { return true }
        if defaults.object(forKey: "liquidGlassEnabled") == nil { return true }
        return defaults.bool(forKey: "liquidGlassEnabled")
    }

    #if canImport(AppKit)
    public static var shouldApplyGlass: Bool {
        isGlassEnabled()
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
    #else
    public static var shouldApplyGlass: Bool { isGlassEnabled() }
    #endif
}
