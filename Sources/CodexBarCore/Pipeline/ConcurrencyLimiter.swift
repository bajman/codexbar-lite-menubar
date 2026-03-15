/// Actor-based bounded concurrency limiter using Swift concurrency primitives.
actor ConcurrencyLimiter {
    private let limit: Int
    private var active: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        precondition(limit > 0, "ConcurrencyLimiter limit must be positive")
        self.limit = limit
    }

    func acquire() async {
        if self.active < self.limit {
            self.active += 1
            return
        }
        await withCheckedContinuation { continuation in
            self.waiters.append(continuation)
        }
    }

    func release() {
        precondition(self.active > 0, "ConcurrencyLimiter: release without matching acquire")
        self.active -= 1
        if !self.waiters.isEmpty {
            let next = self.waiters.removeFirst()
            self.active += 1
            next.resume()
        }
    }
}
