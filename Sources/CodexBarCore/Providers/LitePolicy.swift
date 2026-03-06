import Foundation

public enum LitePolicy {
    public static let allowedKinds: Set<ProviderFetchKind> = [.oauth, .localProbe]

    public static func validateStrategies(_ strategies: [any ProviderFetchStrategy], provider: UsageProvider) {
        #if DEBUG
        for strategy in strategies where !self.allowedKinds.contains(strategy.kind) {
            preconditionFailure("""
            Lite policy violation for \(provider.rawValue): disallowed strategy kind \(strategy.kind)
            """)
        }
        #else
        _ = strategies
        _ = provider
        #endif
    }
}
