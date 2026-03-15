/// Actor-based bounded concurrency limiter using Swift concurrency primitives.
actor ConcurrencyLimiter: Sendable {
    private let limit: Int
    private var active: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        precondition(limit > 0, "ConcurrencyLimiter limit must be positive")
        self.limit = limit
    }

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        precondition(active > 0, "ConcurrencyLimiter: release without matching acquire")
        active -= 1
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            active += 1
            next.resume()
        }
    }
}
