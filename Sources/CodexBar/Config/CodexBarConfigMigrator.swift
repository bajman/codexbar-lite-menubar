import CodexBarCore
import Foundation

struct CodexBarConfigMigrator {
    // Retained for initializer/source compatibility; lite migration no longer imports secrets.
    struct LegacyStores {
        let zaiTokenStore: any ZaiTokenStoring
        let syntheticTokenStore: any SyntheticTokenStoring
        let codexCookieStore: any CookieHeaderStoring
        let claudeCookieStore: any CookieHeaderStoring
        let cursorCookieStore: any CookieHeaderStoring
        let opencodeCookieStore: any CookieHeaderStoring
        let factoryCookieStore: any CookieHeaderStoring
        let minimaxCookieStore: any MiniMaxCookieStoring
        let minimaxAPITokenStore: any MiniMaxAPITokenStoring
        let kimiTokenStore: any KimiTokenStoring
        let kimiK2TokenStore: any KimiK2TokenStoring
        let augmentCookieStore: any CookieHeaderStoring
        let ampCookieStore: any CookieHeaderStoring
        let copilotTokenStore: any CopilotTokenStoring
        let tokenAccountStore: any ProviderTokenAccountStoring
    }

    private struct MigrationState {
        var didUpdate = false
    }

    static func loadOrMigrate(
        configStore: CodexBarConfigStore,
        userDefaults: UserDefaults,
        stores: LegacyStores) -> CodexBarConfig
    {
        _ = stores
        let log = CodexBarLog.logger(LogCategories.configMigration)
        let existing = try? configStore.load()
        var config = (existing ?? CodexBarConfig.makeDefault()).normalized()
        var state = MigrationState()

        if existing == nil {
            self.applyLegacyOrderAndToggles(userDefaults: userDefaults, config: &config, state: &state)
        }

        if state.didUpdate {
            do {
                try configStore.save(config)
            } catch {
                log.error("Failed to persist config: \(error)")
            }
        }

        return config.normalized()
    }

    private static func applyLegacyOrderAndToggles(
        userDefaults: UserDefaults,
        config: inout CodexBarConfig,
        state: inout MigrationState)
    {
        if let order = userDefaults.stringArray(forKey: "providerOrder"), !order.isEmpty {
            config = self.applyProviderOrder(order, config: config)
            state.didUpdate = true
        }
        let toggles = userDefaults.dictionary(forKey: "providerToggles") as? [String: Bool] ?? [:]
        if !toggles.isEmpty {
            config = self.applyProviderToggles(toggles, config: config)
            state.didUpdate = true
        }
    }

    private static func applyProviderOrder(_ raw: [String], config: CodexBarConfig) -> CodexBarConfig {
        let configsByID = Dictionary(uniqueKeysWithValues: config.providers.map { ($0.id, $0) })
        var seen: Set<UsageProvider> = []
        var ordered: [ProviderConfig] = []
        ordered.reserveCapacity(config.providers.count)

        for rawValue in raw {
            guard let provider = UsageProvider(rawValue: rawValue),
                  let entry = configsByID[provider],
                  !seen.contains(provider)
            else { continue }
            seen.insert(provider)
            ordered.append(entry)
        }

        for provider in UsageProvider.allCases where !seen.contains(provider) {
            ordered.append(configsByID[provider] ?? ProviderConfig(id: provider))
        }

        var updated = config
        updated.providers = ordered
        return updated
    }

    private static func applyProviderToggles(
        _ toggles: [String: Bool],
        config: CodexBarConfig) -> CodexBarConfig
    {
        var updated = config
        for index in updated.providers.indices {
            let provider = updated.providers[index].id
            let meta = ProviderDescriptorRegistry.descriptor(for: provider).metadata
            let legacyKey = "show\(provider.rawValue.capitalized)Usage"
            if let toggle = toggles[provider.rawValue] {
                updated.providers[index].enabled = toggle
            } else if let legacy = toggles[legacyKey] {
                updated.providers[index].enabled = legacy
            } else if updated.providers[index].enabled == nil {
                updated.providers[index].enabled = meta.defaultEnabled
            }
        }
        return updated
    }
}
