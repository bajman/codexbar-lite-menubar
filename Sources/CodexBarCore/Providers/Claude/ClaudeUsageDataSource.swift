import Foundation

public enum ClaudeUsageDataSource: String, CaseIterable, Identifiable, Sendable {
    case auto
    case oauth
    case cli
    case web

    public var id: String {
        self.rawValue
    }

    public var displayName: String {
        switch self {
        case .auto: "Auto"
        case .oauth: "OAuth API"
        case .cli: "CLI (Disabled in Lite)"
        case .web: "Web (Disabled in Lite)"
        }
    }

    public var sourceLabel: String {
        switch self {
        case .auto:
            "auto"
        case .oauth:
            "oauth"
        case .cli:
            "cli-disabled"
        case .web:
            "web-disabled"
        }
    }
}
