// Sources/CodexBarCore/Pipeline/AdaptiveRefreshTimer.swift
import Foundation

/// Activity-aware polling timer with three states.
actor AdaptiveRefreshTimer {
    enum State: Sendable, Equatable {
        case active    // FSEvents in last 15 min → 2 min poll
        case idle      // No FSEvents 15-60 min → 15 min poll
        case deepIdle  // No FSEvents 60+ min → 30 min poll
    }

    private(set) var state: State = .idle
    private var lastFSEventTimestamp: Date?
    private var paused: Bool = false
    private let nowProvider: @Sendable () -> Date

    init(nowProvider: @escaping @Sendable () -> Date = { Date() }) {
        self.nowProvider = nowProvider
    }

    func recordFSEvent() {
        lastFSEventTimestamp = nowProvider()
        state = .active
    }

    var currentInterval: Duration {
        switch state {
        case .active:   return .seconds(120)
        case .idle:     return .seconds(900)
        case .deepIdle: return .seconds(1800)
        }
    }

    func evaluateState() {
        guard let last = lastFSEventTimestamp else {
            state = .deepIdle
            return
        }
        let elapsed = nowProvider().timeIntervalSince(last)
        switch elapsed {
        case ..<900:    state = .active
        case ..<3600:   state = .idle
        default:        state = .deepIdle
        }
    }

    func pause() { paused = true }
    func resume() { paused = false }
    var isPaused: Bool { paused }
}
