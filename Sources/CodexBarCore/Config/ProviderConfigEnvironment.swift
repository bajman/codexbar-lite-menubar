import Foundation

public enum ProviderConfigEnvironment {
    public static func applyAPIKeyOverride(
        base: [String: String],
        provider _: UsageProvider,
        config _: ProviderConfig?) -> [String: String]
    {
        base
    }
}
