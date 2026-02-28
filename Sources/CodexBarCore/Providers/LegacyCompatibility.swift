import Foundation

public enum GeminiStatusProbeError: LocalizedError, Sendable {
    case geminiNotInstalled
    case timedOut
    case parseFailed

    public var errorDescription: String? {
        switch self {
        case .geminiNotInstalled:
            "Gemini CLI is not installed."
        case .timedOut:
            "Gemini request timed out."
        case .parseFailed:
            "Gemini response parse failed."
        }
    }
}

public struct AntigravityPlanInfoSummary: Codable, Sendable {
    public let planName: String?
    public let planDisplayName: String?
    public let displayName: String?
    public let productName: String?
    public let planShortName: String?

    public init(
        planName: String? = nil,
        planDisplayName: String? = nil,
        displayName: String? = nil,
        productName: String? = nil,
        planShortName: String? = nil)
    {
        self.planName = planName
        self.planDisplayName = planDisplayName
        self.displayName = displayName
        self.productName = productName
        self.planShortName = planShortName
    }
}

public struct AntigravityStatusProbe {
    public init() {}

    public static func isRunning() async -> Bool {
        false
    }

    public func fetchPlanInfoSummary() async throws -> AntigravityPlanInfoSummary {
        AntigravityPlanInfoSummary()
    }
}

public struct AugmentStatusProbe {
    public init() {}

    public static func latestDumps() async -> String {
        ""
    }

    public func debugRawProbe() async -> String {
        ""
    }
}

public enum MiniMaxCookieHeader {
    public static func normalized(from raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw
    }
}
