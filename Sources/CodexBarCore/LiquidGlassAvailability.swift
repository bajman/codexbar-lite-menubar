import Foundation

#if canImport(SwiftUI)
import SwiftUI
#endif

#if canImport(AppKit)
import AppKit
#endif

public enum LiquidGlassLayer: String, Codable, Sendable {
    /// Thick glass surface, used for larger containers.
    case shell
    /// Thin glass surface, used for cards and panels.
    case card
    /// Ultra-thin glass surface, used for pill styles.
    case pill
    /// No liquid-glass style.
    case none
}

public enum LiquidGlassAvailability: Sendable {
    public static func isGlassEnabled(
        defaults: UserDefaults? = .standard) -> Bool
    {
        guard let defaults else { return true }
        if defaults.object(forKey: "liquidGlassEnabled") == nil { return true }
        return defaults.bool(forKey: "liquidGlassEnabled")
    }

    #if canImport(AppKit)
    public static var shouldApplyGlass: Bool {
        guard #available(macOS 26.4, *) else { return false }
        return isGlassEnabled()
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
    #else
    public static var shouldApplyGlass: Bool {
        false
    }
    #endif
}

#if canImport(SwiftUI)
public struct LiquidGlassActiveKey: EnvironmentKey {
    public static let defaultValue = LiquidGlassAvailability.shouldApplyGlass
}

extension EnvironmentValues {
    public var liquidGlassActive: Bool {
        get { self[LiquidGlassActiveKey.self] }
        set { self[LiquidGlassActiveKey.self] = newValue }
    }
}
#endif
