// Sources/CodexBarCore/Pipeline/CoalescingEngine.swift
import Foundation

/// Handles request merging and minimum interval enforcement.
struct CoalescingEngine: Sendable {
    enum FetchKind: Sendable {
        case quota
        case tokenCost
        case status
    }

    private var pendingRequest: RefreshRequest?
    private var lastCompletion: [String: Date] = [:]

    private static let minimumIntervals: [FetchKind: [RefreshRequest.Priority: TimeInterval]] = [
        .quota: [.p0: 0, .p1: 30, .p2: 60, .p3: 60],
        .tokenCost: [.p0: 0, .p1: 10, .p2: 300, .p3: 300],
        .status: [.p0: 0, .p1: 60, .p2: 600, .p3: 600],
    ]

    mutating func mergeRefreshRequest(_ request: RefreshRequest) {
        if var existing = pendingRequest {
            existing.merge(request)
            self.pendingRequest = existing
        } else {
            self.pendingRequest = request
        }
    }

    mutating func drainPendingRequest() -> RefreshRequest? {
        defer { pendingRequest = nil }
        return self.pendingRequest
    }

    func shouldSkip(provider: UsageProvider, kind: FetchKind, priority: RefreshRequest.Priority) -> Bool {
        if priority == .p0 { return false }
        let key = "\(provider):\(kind)"
        guard let last = lastCompletion[key] else { return false }
        let minInterval = Self.minimumIntervals[kind]?[priority] ?? 60
        return Date().timeIntervalSince(last) < minInterval
    }

    mutating func recordCompletion(provider: UsageProvider, kind: FetchKind) {
        self.lastCompletion["\(provider):\(kind)"] = Date()
    }

    /// Whether a pending request exists (without draining it).
    var hasPending: Bool {
        self.pendingRequest != nil
    }
}
