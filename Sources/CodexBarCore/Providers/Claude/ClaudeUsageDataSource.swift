import Foundation

public enum ClaudeUsageSourceLabels {
    public static let automatic = "auto"
    public static let live = "claude-code"
    public static let local = "local"
}

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
        case .auto: "Automatic"
        case .oauth: "Claude Code only"
        case .cli: "CLI (Disabled in Lite)"
        case .web: "Web (Disabled in Lite)"
        }
    }

    public var sourceLabel: String {
        switch self {
        case .auto:
            ClaudeUsageSourceLabels.live
        case .oauth:
            ClaudeUsageSourceLabels.live
        case .cli:
            "cli-disabled"
        case .web:
            "web-disabled"
        }
    }
}
