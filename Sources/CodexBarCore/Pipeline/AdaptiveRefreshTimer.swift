// Sources/CodexBarCore/Pipeline/AdaptiveRefreshTimer.swift
import Foundation

/// Activity-aware polling timer with three states.
public actor AdaptiveRefreshTimer {
    public enum State: Sendable, Equatable {
        case active // FSEvents in last 15 min -> 2 min poll
        case idle // No FSEvents 15-60 min -> 15 min poll
        case deepIdle // No FSEvents 60+ min -> 30 min poll
    }

    private(set) var state: State = .idle
    private var lastFSEventTimestamp: Date?
    private var paused: Bool = false
    private let nowProvider: @Sendable () -> Date

    public init(nowProvider: @escaping @Sendable () -> Date = { Date() }) {
        self.nowProvider = nowProvider
    }

    public func recordFSEvent() {
        self.lastFSEventTimestamp = self.nowProvider()
        self.state = .active
    }

    public var currentInterval: Duration {
        switch self.state {
        case .active: .seconds(120)
        case .idle: .seconds(900)
        case .deepIdle: .seconds(1800)
        }
    }

    public func evaluateState() {
        guard let last = lastFSEventTimestamp else {
            self.state = .deepIdle
            return
        }
        let elapsed = self.nowProvider().timeIntervalSince(last)
        switch elapsed {
        case ..<900: self.state = .active
        case ..<3600: self.state = .idle
        default: self.state = .deepIdle
        }
    }

    public func pause() {
        self.paused = true
    }

    public func resume() {
        self.paused = false
    }

    public var isPaused: Bool {
        self.paused
    }
}
