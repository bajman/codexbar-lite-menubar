import Foundation

public struct CodexBarConfig: Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var providers: [ProviderConfig]

    public init(version: Int = Self.currentVersion, providers: [ProviderConfig]) {
        self.version = version
        self.providers = providers
    }

    public static func makeDefault(
        metadata: [UsageProvider: ProviderMetadata] = ProviderDescriptorRegistry.metadata) -> CodexBarConfig
    {
        let providers = UsageProvider.allCases.map { provider in
            ProviderConfig(
                id: provider,
                enabled: metadata[provider]?.defaultEnabled,
                source: .auto)
        }
        return CodexBarConfig(version: Self.currentVersion, providers: providers)
    }

    public func normalized(
        metadata: [UsageProvider: ProviderMetadata] = ProviderDescriptorRegistry.metadata) -> CodexBarConfig
    {
        var seen: Set<UsageProvider> = []
        var normalized: [ProviderConfig] = []
        normalized.reserveCapacity(max(self.providers.count, UsageProvider.allCases.count))

        for provider in self.providers {
            guard !seen.contains(provider.id) else { continue }
            seen.insert(provider.id)
            normalized.append(provider.normalized())
        }

        for provider in UsageProvider.allCases where !seen.contains(provider) {
            normalized.append(ProviderConfig(
                id: provider,
                enabled: metadata[provider]?.defaultEnabled,
                source: .auto))
        }

        return CodexBarConfig(
            version: Self.currentVersion,
            providers: normalized)
    }

    public func orderedProviders() -> [UsageProvider] {
        self.providers.map(\.id)
    }

    public func enabledProviders(
        metadata: [UsageProvider: ProviderMetadata] = ProviderDescriptorRegistry.metadata) -> [UsageProvider]
    {
        self.providers.compactMap { config in
            let enabled = config.enabled ?? metadata[config.id]?.defaultEnabled ?? false
            return enabled ? config.id : nil
        }
    }

    public func providerConfig(for id: UsageProvider) -> ProviderConfig? {
        self.providers.first(where: { $0.id == id })
    }

    public mutating func setProviderConfig(_ config: ProviderConfig) {
        let normalized = config.normalized()
        if let index = self.providers.firstIndex(where: { $0.id == normalized.id }) {
            self.providers[index] = normalized
        } else {
            self.providers.append(normalized)
        }
    }
}

public struct ProviderConfig: Codable, Sendable, Identifiable {
    public let id: UsageProvider
    public var enabled: Bool?
    public var source: ProviderSourceMode?
    // Legacy compatibility fields kept for compile-time API stability.
    // Lite contract: these are decode-only shims and are never persisted.
    public var apiKey: String?
    public var cookieHeader: String?
    public var cookieSource: ProviderCookieSource?
    public var region: String?
    public var workspaceID: String?
    public var tokenAccounts: ProviderTokenAccountData?

    private enum CodingKeys: String, CodingKey {
        case id
        case enabled
        case source
        case apiKey
        case cookieHeader
        case cookieSource
        case region
        case workspaceID
        case tokenAccounts
    }

    public init(
        id: UsageProvider,
        enabled: Bool? = nil,
        source: ProviderSourceMode? = nil,
        apiKey: String? = nil,
        cookieHeader: String? = nil,
        cookieSource: ProviderCookieSource? = nil,
        region: String? = nil,
        workspaceID: String? = nil,
        tokenAccounts: ProviderTokenAccountData? = nil)
    {
        self.id = id
        self.enabled = enabled
        self.source = source
        // Never keep secret/legacy fields in-memory after normalization in lite mode.
        _ = apiKey
        _ = cookieHeader
        _ = cookieSource
        _ = region
        _ = workspaceID
        _ = tokenAccounts
        self.apiKey = nil
        self.cookieHeader = nil
        self.cookieSource = nil
        self.region = nil
        self.workspaceID = nil
        self.tokenAccounts = nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UsageProvider.self, forKey: .id)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
        self.source = try container.decodeIfPresent(ProviderSourceMode.self, forKey: .source)
        // Decode legacy fields for forward/backward compatibility but drop values immediately.
        _ = try container.decodeIfPresent(String.self, forKey: .apiKey)
        _ = try container.decodeIfPresent(String.self, forKey: .cookieHeader)
        _ = try container.decodeIfPresent(ProviderCookieSource.self, forKey: .cookieSource)
        _ = try container.decodeIfPresent(String.self, forKey: .region)
        _ = try container.decodeIfPresent(String.self, forKey: .workspaceID)
        _ = try container.decodeIfPresent(ProviderTokenAccountData.self, forKey: .tokenAccounts)
        self.apiKey = nil
        self.cookieHeader = nil
        self.cookieSource = nil
        self.region = nil
        self.workspaceID = nil
        self.tokenAccounts = nil
    }

    /// Lite contract: persist only id/enabled/source.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encodeIfPresent(self.enabled, forKey: .enabled)
        try container.encodeIfPresent(self.source, forKey: .source)
    }

    public func normalized() -> ProviderConfig {
        let normalizedSource: ProviderSourceMode? = switch self.source {
        case .oauth:
            .oauth
        case .auto, .none, .web, .cli, .api:
            .auto
        }

        return ProviderConfig(
            id: self.id,
            enabled: self.enabled,
            source: normalizedSource)
    }

    public var sanitizedAPIKey: String? {
        Self.clean(self.apiKey)
    }

    public var sanitizedCookieHeader: String? {
        Self.clean(self.cookieHeader)
    }

    private static func clean(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
            (value.hasPrefix("'") && value.hasSuffix("'"))
        {
            value.removeFirst()
            value.removeLast()
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
