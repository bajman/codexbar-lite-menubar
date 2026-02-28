import CodexBarCore

// Compatibility shims for removed provider settings. These are intentionally no-op in lite mode.
extension SettingsStore {
    var cursorCookieSource: ProviderCookieSource {
        get { .off }
        set {}
    }

    var opencodeCookieSource: ProviderCookieSource {
        get { .off }
        set {}
    }

    var factoryCookieSource: ProviderCookieSource {
        get { .off }
        set {}
    }

    var minimaxCookieSource: ProviderCookieSource {
        get { .off }
        set {}
    }

    var kimiCookieSource: ProviderCookieSource {
        get { .off }
        set {}
    }

    var augmentCookieSource: ProviderCookieSource {
        get { .off }
        set {}
    }

    var ampCookieSource: ProviderCookieSource {
        get { .off }
        set {}
    }

    var ollamaCookieSource: ProviderCookieSource {
        get { .off }
        set {}
    }

    var cursorCookieHeader: String {
        get { "" }
        set {}
    }

    var opencodeCookieHeader: String {
        get { "" }
        set {}
    }

    var factoryCookieHeader: String {
        get { "" }
        set {}
    }

    var minimaxCookieHeader: String {
        get { "" }
        set {}
    }

    var kimiManualCookieHeader: String {
        get { "" }
        set {}
    }

    var augmentCookieHeader: String {
        get { "" }
        set {}
    }

    var ampCookieHeader: String {
        get { "" }
        set {}
    }

    var ollamaCookieHeader: String {
        get { "" }
        set {}
    }

    var opencodeWorkspaceID: String {
        get { "" }
        set {}
    }

    var minimaxAPIToken: String {
        get { "" }
        set {}
    }

    var minimaxAPIRegion: MiniMaxAPIRegion {
        get { .global }
        set {}
    }

    var kimiK2APIToken: String {
        get { "" }
        set {}
    }

    var zaiAPIToken: String {
        get { "" }
        set {}
    }

    var syntheticAPIToken: String {
        get { "" }
        set {}
    }

    var copilotAPIToken: String {
        get { "" }
        set {}
    }

    var warpAPIToken: String {
        get { "" }
        set {}
    }
}
