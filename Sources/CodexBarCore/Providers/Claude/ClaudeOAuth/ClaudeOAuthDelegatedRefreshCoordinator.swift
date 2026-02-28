import Foundation

public enum ClaudeOAuthDelegatedRefreshCoordinator {
    public enum Outcome: Sendable, Equatable {
        case skippedByCooldown
        case cliUnavailable
        case attemptedSucceeded
        case attemptedFailed(String)
    }

    public static func attempt(now _: Date = Date(), timeout _: TimeInterval = 8) async -> Outcome {
        .cliUnavailable
    }

    public static func isInCooldown(now _: Date = Date()) -> Bool {
        false
    }

    public static func cooldownRemainingSeconds(now _: Date = Date()) -> Int? {
        nil
    }

    public static func isClaudeCLIAvailable() -> Bool {
        ProviderVersionDetector.claudeVersion() != nil
    }
}
