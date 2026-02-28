import CodexBarCore

/// Compatibility shims for removed provider settings. These are intentionally no-op in lite mode.
extension SettingsStore {
    var cursorCookieSource: ProviderCookieSource {
        get { .off }
        set { _ = newValue }
    }

    var opencodeCookieSource: ProviderCookieSource {
        get { .off }
        set { _ = newValue }
    }

    var factoryCookieSource: ProviderCookieSource {
        get { .off }
        set { _ = newValue }
    }

    var minimaxCookieSource: ProviderCookieSource {
        get { .off }
        set { _ = newValue }
    }

    var kimiCookieSource: ProviderCookieSource {
        get { .off }
        set { _ = newValue }
    }

    var augmentCookieSource: ProviderCookieSource {
        get { .off }
        set { _ = newValue }
    }

    var ampCookieSource: ProviderCookieSource {
        get { .off }
        set { _ = newValue }
    }

    var ollamaCookieSource: ProviderCookieSource {
        get { .off }
        set { _ = newValue }
    }

    var cursorCookieHeader: String {
        get { "" }
        set { _ = newValue }
    }

    var opencodeCookieHeader: String {
        get { "" }
        set { _ = newValue }
    }

    var factoryCookieHeader: String {
        get { "" }
        set { _ = newValue }
    }

    var minimaxCookieHeader: String {
        get { "" }
        set { _ = newValue }
    }

    var kimiManualCookieHeader: String {
        get { "" }
        set { _ = newValue }
    }

    var augmentCookieHeader: String {
        get { "" }
        set { _ = newValue }
    }

    var ampCookieHeader: String {
        get { "" }
        set { _ = newValue }
    }

    var ollamaCookieHeader: String {
        get { "" }
        set { _ = newValue }
    }

    var opencodeWorkspaceID: String {
        get { "" }
        set { _ = newValue }
    }

    var minimaxAPIToken: String {
        get { "" }
        set { _ = newValue }
    }

    var minimaxAPIRegion: MiniMaxAPIRegion {
        get { .global }
        set { _ = newValue }
    }

    var kimiK2APIToken: String {
        get { "" }
        set { _ = newValue }
    }

    var zaiAPIToken: String {
        get { "" }
        set { _ = newValue }
    }

    var syntheticAPIToken: String {
        get { "" }
        set { _ = newValue }
    }

    var copilotAPIToken: String {
        get { "" }
        set { _ = newValue }
    }

    var warpAPIToken: String {
        get { "" }
        set { _ = newValue }
    }
}
