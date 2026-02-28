import Foundation

public enum Browser: String, CaseIterable, Sendable, Hashable {
    case safari
    case firefox
    case zen
    case chrome
    case chromeBeta
    case chromeCanary
    case arc
    case arcBeta
    case arcCanary
    case chatgptAtlas
    case chromium
    case brave
    case braveBeta
    case braveNightly
    case edge
    case edgeBeta
    case edgeCanary
    case helium
    case vivaldi
    case dia

    public static var defaultImportOrder: [Browser] {
        []
    }

    public static var safeStorageLabels: [(service: String, account: String)] {
        []
    }

    var appBundleName: String? {
        nil
    }

    var chromiumProfileRelativePath: String? {
        nil
    }

    var geckoProfilesFolder: String? {
        nil
    }

    var usesGeckoProfileStore: Bool {
        false
    }

    var usesChromiumProfileStore: Bool {
        false
    }

    var usesKeychainForCookieDecryption: Bool {
        false
    }
}

public typealias BrowserCookieImportOrder = [Browser]

extension [Browser] {
    public func cookieImportCandidates(using _: BrowserDetection) -> [Browser] {
        []
    }

    public func browsersWithProfileData(using _: BrowserDetection) -> [Browser] {
        []
    }

    public var loginHint: String {
        "your authenticated browser"
    }
}
