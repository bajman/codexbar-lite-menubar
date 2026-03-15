// Sources/CodexBarCore/Pipeline/RefreshRequest.swift
/// Describes a data refresh request with priority and scope.
struct RefreshRequest: Sendable {
    /// Which providers to refresh. Empty = all enabled providers.
    var providers: Set<UsageProvider> = []

    /// Force token cost usage recalculation even if cache is fresh.
    var forceTokenUsage: Bool = false

    /// Force provider status page checks even if cache is fresh.
    var forceStatusChecks: Bool = false

    /// Force quota probe even if within minimum interval.
    /// Only respected for P0 (user-initiated) priority.
    var forceQuota: Bool = false

    /// The priority tier for this request.
    var priority: Priority = .p2

    enum Priority: Int, Comparable, Sendable {
        case p0 = 0  // user action, wake-from-sleep, credential change
        case p1 = 1  // FSEvents JSONL write
        case p2 = 2  // adaptive timer poll
        case p3 = 3  // background maintenance

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Merge another request into this one, keeping highest priority and OR-ing flags.
    mutating func merge(_ other: RefreshRequest) {
        providers.formUnion(other.providers)
        forceTokenUsage = forceTokenUsage || other.forceTokenUsage
        forceStatusChecks = forceStatusChecks || other.forceStatusChecks
        forceQuota = forceQuota || other.forceQuota
        priority = min(priority, other.priority)
    }
}
