/// Sources/CodexBarCore/Pipeline/RefreshRequest.swift
/// Describes a data refresh request with priority and scope.
public struct RefreshRequest: Sendable {
    /// Which providers to refresh. Empty = all enabled providers.
    public var providers: Set<UsageProvider> = []

    /// Force token cost usage recalculation even if cache is fresh.
    public var forceTokenUsage: Bool = false

    /// Force provider status page checks even if cache is fresh.
    public var forceStatusChecks: Bool = false

    /// Force quota probe even if within minimum interval.
    /// Only respected for P0 (user-initiated) priority.
    public var forceQuota: Bool = false

    /// The priority tier for this request.
    public var priority: Priority = .p2

    public enum Priority: Int, Comparable, Sendable {
        case p0 = 0 // user action, wake-from-sleep, credential change
        case p1 = 1 // FSEvents JSONL write
        case p2 = 2 // adaptive timer poll
        case p3 = 3 // background maintenance

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public init(
        providers: Set<UsageProvider> = [],
        forceQuota: Bool = false,
        forceTokenUsage: Bool = false,
        forceStatusChecks: Bool = false,
        priority: Priority = .p2)
    {
        self.providers = providers
        self.forceQuota = forceQuota
        self.forceTokenUsage = forceTokenUsage
        self.forceStatusChecks = forceStatusChecks
        self.priority = priority
    }

    /// Merge another request into this one, keeping highest priority and OR-ing flags.
    public mutating func merge(_ other: RefreshRequest) {
        self.providers.formUnion(other.providers)
        self.forceTokenUsage = self.forceTokenUsage || other.forceTokenUsage
        self.forceStatusChecks = self.forceStatusChecks || other.forceStatusChecks
        self.forceQuota = self.forceQuota || other.forceQuota
        self.priority = min(self.priority, other.priority)
    }
}
