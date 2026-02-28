import Foundation

public enum WebKitTeardown {
    public static func retain(_: AnyObject) {}

    public static func scheduleCleanup(
        owner _: AnyObject,
        window _: AnyObject?,
        webView _: AnyObject?)
    {}
}

public actor CursorSessionStore {
    public static let shared = CursorSessionStore()
    private var cookies: [HTTPCookie] = []

    public func setCookies(_ cookies: [HTTPCookie]) {
        self.cookies = cookies
    }

    public func allCookies() -> [HTTPCookie] {
        self.cookies
    }
}

public struct CursorStatusSnapshot: Sendable {
    public let membershipType: String?
    public let accountEmail: String?
    public let planPercentUsed: Double
    public let planUsedUSD: Double
    public let planLimitUSD: Double
    public let onDemandUsedUSD: Double
    public let onDemandLimitUSD: Double?
    public let teamOnDemandUsedUSD: Double?
    public let teamOnDemandLimitUSD: Double?
    public let billingCycleEnd: Date?
    public let rawJSON: String?

    public init(
        membershipType: String? = nil,
        accountEmail: String? = nil,
        planPercentUsed: Double = 0,
        planUsedUSD: Double = 0,
        planLimitUSD: Double = 0,
        onDemandUsedUSD: Double = 0,
        onDemandLimitUSD: Double? = nil,
        teamOnDemandUsedUSD: Double? = nil,
        teamOnDemandLimitUSD: Double? = nil,
        billingCycleEnd: Date? = nil,
        rawJSON: String? = nil)
    {
        self.membershipType = membershipType
        self.accountEmail = accountEmail
        self.planPercentUsed = planPercentUsed
        self.planUsedUSD = planUsedUSD
        self.planLimitUSD = planLimitUSD
        self.onDemandUsedUSD = onDemandUsedUSD
        self.onDemandLimitUSD = onDemandLimitUSD
        self.teamOnDemandUsedUSD = teamOnDemandUsedUSD
        self.teamOnDemandLimitUSD = teamOnDemandLimitUSD
        self.billingCycleEnd = billingCycleEnd
        self.rawJSON = rawJSON
    }
}

public struct CursorStatusProbe {
    public init(browserDetection _: BrowserDetection) {}

    public func fetch(_ logger: @escaping (String) -> Void = { _ in }) async throws -> CursorStatusSnapshot {
        logger("Cursor probe disabled in lite build.")
        return CursorStatusSnapshot()
    }

    public func fetchWithManualCookies(_: String) async throws -> CursorStatusSnapshot {
        CursorStatusSnapshot()
    }
}

public struct AmpUsageFetcher {
    public init(browserDetection _: BrowserDetection) {}

    public func debugRawProbe(cookieHeaderOverride _: String?) async -> String {
        "Amp probe disabled in lite build."
    }
}

public struct OllamaUsageFetcher {
    public init(browserDetection _: BrowserDetection) {}

    public func debugRawProbe(cookieHeaderOverride _: String?, manualCookieMode _: Bool) async -> String {
        "Ollama probe disabled in lite build."
    }
}

public enum OpenRouterSettingsReader {
    public static func apiToken(environment _: [String: String]) -> String? {
        nil
    }
}

public enum ClaudeWebAPIFetcher {
    public struct ExtraUsageCost: Sendable {
        public let used: Double
        public let limit: Double
        public let currencyCode: String
        public let period: String?
        public let resetsAt: Date?

        public init(
            used: Double = 0,
            limit: Double = 0,
            currencyCode: String = "USD",
            period: String? = nil,
            resetsAt: Date? = nil)
        {
            self.used = used
            self.limit = limit
            self.currencyCode = currencyCode
            self.period = period
            self.resetsAt = resetsAt
        }
    }

    public struct Usage: Sendable {
        public let sessionPercentUsed: Double
        public let sessionResetsAt: Date?
        public let weeklyPercentUsed: Double?
        public let weeklyResetsAt: Date?
        public let opusPercentUsed: Double?
        public let extraUsageCost: ExtraUsageCost?

        public init(
            sessionPercentUsed: Double = 0,
            sessionResetsAt: Date? = nil,
            weeklyPercentUsed: Double? = nil,
            weeklyResetsAt: Date? = nil,
            opusPercentUsed: Double? = nil,
            extraUsageCost: ExtraUsageCost? = nil)
        {
            self.sessionPercentUsed = sessionPercentUsed
            self.sessionResetsAt = sessionResetsAt
            self.weeklyPercentUsed = weeklyPercentUsed
            self.weeklyResetsAt = weeklyResetsAt
            self.opusPercentUsed = opusPercentUsed
            self.extraUsageCost = extraUsageCost
        }
    }

    public static func hasSessionKey(cookieHeader _: String) -> Bool {
        false
    }

    public static func hasSessionKey(
        browserDetection _: BrowserDetection,
        logger: @escaping (String) -> Void) -> Bool
    {
        logger("Claude web probe disabled in lite build.")
        return false
    }

    public static func fetchUsage(
        browserDetection _: BrowserDetection,
        logger: @escaping (String) -> Void) async throws -> Usage
    {
        logger("Claude web usage fetch disabled in lite build.")
        return Usage()
    }
}

public struct ZaiModelUsageEntry: Codable, Sendable {
    public let modelCode: String
    public let usage: Int

    public init(modelCode: String, usage: Int) {
        self.modelCode = modelCode
        self.usage = usage
    }
}

public struct ZaiLimitEntry: Codable, Sendable {
    public let currentValue: Int?
    public let usage: Int?
    public let remaining: Int?
    public let usageDetails: [ZaiModelUsageEntry]
    public let windowLabel: String?
    public let nextResetTime: Date?

    public init(
        currentValue: Int? = nil,
        usage: Int? = nil,
        remaining: Int? = nil,
        usageDetails: [ZaiModelUsageEntry] = [],
        windowLabel: String? = nil,
        nextResetTime: Date? = nil)
    {
        self.currentValue = currentValue
        self.usage = usage
        self.remaining = remaining
        self.usageDetails = usageDetails
        self.windowLabel = windowLabel
        self.nextResetTime = nextResetTime
    }
}

public struct ZaiUsageSnapshot: Codable, Sendable {
    public let tokenLimit: ZaiLimitEntry?
    public let timeLimit: ZaiLimitEntry?

    public init(tokenLimit: ZaiLimitEntry? = nil, timeLimit: ZaiLimitEntry? = nil) {
        self.tokenLimit = tokenLimit
        self.timeLimit = timeLimit
    }
}

public enum OpenRouterKeyQuotaStatus: String, Codable, Sendable {
    case available
    case noLimitConfigured
    case unavailable
    case limited
}

public struct OpenRouterUsageSnapshot: Codable, Sendable {
    public let keyQuotaStatus: OpenRouterKeyQuotaStatus
    public let keyRemaining: Double?
    public let keyLimit: Double?

    public init(
        keyQuotaStatus: OpenRouterKeyQuotaStatus = .noLimitConfigured,
        keyRemaining: Double? = nil,
        keyLimit: Double? = nil)
    {
        self.keyQuotaStatus = keyQuotaStatus
        self.keyRemaining = keyRemaining
        self.keyLimit = keyLimit
    }

    public var hasValidKeyQuota: Bool {
        self.keyRemaining != nil && self.keyLimit != nil
    }
}

extension UsageSnapshot {
    public var zaiUsage: ZaiUsageSnapshot? {
        nil
    }

    public var openRouterUsage: OpenRouterUsageSnapshot? {
        nil
    }
}
