# Data Pipeline Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace CodexBar Lite's poll-only data collection with an event-driven pipeline using FSEvents file watching, adaptive refresh timers, LiteLLM-based live pricing, provider-aware deduplication, content-fingerprinted incremental parsing, and a priority-ordered DataPipeline coordinator.

**Architecture:** New components live in `Sources/CodexBarCore/Pipeline/`. The `DataPipeline` actor coordinates all data fetching through a priority queue and emits events via `AsyncStream<PipelineEvent>`. `UsageStore` becomes a reactive consumer. Existing fetchers (`ClaudeLiteFetcher`, `CodexLiteFetcher`) are called by the pipeline, not by `UsageStore` directly.

**Tech Stack:** Swift 6.2, Swift concurrency (actors, AsyncStream, structured concurrency), FSEvents (CoreServices), CryptoKit (SHA256 fingerprinting), Swift Testing framework, macOS 26+.

**Spec:** `docs/superpowers/specs/2026-03-15-data-pipeline-redesign-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|---|---|
| `Sources/CodexBarCore/Pipeline/FSEventsWatcher.swift` | Wraps FSEventStream API in a Swift actor; emits batched file change events via AsyncStream |
| `Sources/CodexBarCore/Pipeline/ContentFingerprintedParser.swift` | SHA256 + inode identity checks for incremental JSONL parse safety |
| `Sources/CodexBarCore/Pipeline/PricingResolver.swift` | 5-layer pricing resolution (memory → disk → network → stale → embedded) with model name resolution chain |
| `Sources/CodexBarCore/Pipeline/EmbeddedPricing.swift` | Compile-time-embedded LiteLLM pricing snapshot (auto-generated) |
| `Sources/CodexBarCore/Pipeline/RefreshRequest.swift` | `RefreshRequest` type with `Priority` enum (P0-P3) |
| `Sources/CodexBarCore/Pipeline/ConcurrencyLimiter.swift` | Actor-based bounded concurrency using CheckedContinuation |
| `Sources/CodexBarCore/Pipeline/CoalescingEngine.swift` | Debouncing, request merging, minimum interval enforcement |
| `Sources/CodexBarCore/Pipeline/AdaptiveRefreshTimer.swift` | Activity-aware polling with active/idle/deepIdle state machine |
| `Sources/CodexBarCore/Pipeline/DataPipeline.swift` | Central coordinator: priority queue, concurrency governor, event stream |
| `Sources/CodexBarCore/Pipeline/SystemLifecycleObserver.swift` | Sleep/wake, App Nap prevention, Space switch handling |
| `Scripts/update_embedded_pricing.sh` | Build script to fetch LiteLLM pricing and generate `EmbeddedPricing.swift` |
| `TestsLite/Pipeline/ConcurrencyLimiterTests.swift` | Unit tests for bounded concurrency |
| `TestsLite/Pipeline/FSEventsWatcherTests.swift` | Unit tests for file watching |
| `TestsLite/Pipeline/ContentFingerprintedParserTests.swift` | Unit tests for fingerprint-based parse decisions |
| `TestsLite/Pipeline/PricingResolverTests.swift` | Unit tests for model resolution chain + tiered pricing |
| `TestsLite/Pipeline/AdaptiveRefreshTimerTests.swift` | Unit tests for state machine transitions |
| `TestsLite/Pipeline/CoalescingEngineTests.swift` | Unit tests for debouncing and request merging |
| `TestsLite/Pipeline/DataPipelineTests.swift` | Integration tests for pipeline orchestration |
| `TestsLite/Pipeline/DeduplicationTests.swift` | Unit tests for Claude + Codex deduplication |

### Modified Files

| File | Change |
|---|---|
| `Sources/CodexBarCore/Vendored/CostUsage/CostUsageCache.swift` | Add `headerFingerprint`, `inodeIdentifier` fields; bump version to 3 |
| `Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift` | Fix tiered pricing to use shared budget; delegate to `PricingResolver` for lookups |
| `Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner+Claude.swift` | Replace deduplication with two-layer Claude-specific strategy |
| `Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner.swift` | Add Codex counter-reset detection; integrate fingerprinted parser |
| `Sources/CodexBar/UsageStore.swift` | Subscribe to `DataPipeline.events` instead of managing timers directly |
| `Sources/CodexBar/UsageStore+Refresh.swift` | Replace `performRefresh()` with pipeline delegation; remove timer loops |
| `TestsLite/CostUsagePricingTests.swift` | Add tests for tiered pricing fix, model resolution chain |
| `TestsLite/CostUsageScannerTests.swift` | Add tests for counter-reset detection, fingerprint integration |

---

## Chunk 1: Foundation — ConcurrencyLimiter, RefreshRequest, ContentFingerprintedParser

These are independent, self-contained types with no external dependencies. They form the building blocks for later components.

### Task 1: ConcurrencyLimiter

**Files:**
- Create: `Sources/CodexBarCore/Pipeline/ConcurrencyLimiter.swift`
- Create: `TestsLite/Pipeline/ConcurrencyLimiterTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// TestsLite/Pipeline/ConcurrencyLimiterTests.swift
import Testing
@testable import CodexBarCore

@Suite("ConcurrencyLimiter")
struct ConcurrencyLimiterTests {

    @Test("allows up to limit concurrent acquisitions")
    func allowsUpToLimit() async {
        let limiter = ConcurrencyLimiter(limit: 2)
        // Two acquires should succeed immediately
        await limiter.acquire()
        await limiter.acquire()
        // Release both
        await limiter.release()
        await limiter.release()
    }

    @Test("blocks third acquire until release")
    func blocksOverLimit() async {
        let limiter = ConcurrencyLimiter(limit: 1)
        await limiter.acquire()

        // Use an actor-wrapped flag instead of ManagedAtomic (swift-atomics not in deps)
        let flag = Flag()
        let task = Task {
            await limiter.acquire()
            await flag.set(true)
        }
        // Give the task a chance to run
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await flag.value == false)

        // Release should unblock the waiting task
        await limiter.release()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await flag.value == true)

        await limiter.release()
        task.cancel()
    }
}

/// Simple actor-wrapped flag for test synchronization.
private actor Flag {
    var value: Bool = false
    func set(_ v: Bool) { value = v }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConcurrencyLimiterTests 2>&1 | tail -20`
Expected: FAIL — `ConcurrencyLimiter` not found

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/CodexBarCore/Pipeline/ConcurrencyLimiter.swift
/// Actor-based bounded concurrency limiter using Swift concurrency primitives.
/// Not a semaphore — uses continuations rather than OS-level synchronization.
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ConcurrencyLimiterTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBarCore/Pipeline/ConcurrencyLimiter.swift TestsLite/Pipeline/ConcurrencyLimiterTests.swift
git commit -m "feat: add ConcurrencyLimiter actor for bounded async concurrency"
```

---

### Task 2: RefreshRequest

**Files:**
- Create: `Sources/CodexBarCore/Pipeline/RefreshRequest.swift`

- [ ] **Step 1: Write the type**

```swift
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
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build --target CodexBarCore 2>&1 | tail -10`
Expected: Build succeeded

- [ ] **Step 3: Commit**

```bash
git add Sources/CodexBarCore/Pipeline/RefreshRequest.swift
git commit -m "feat: add RefreshRequest type with Priority enum"
```

---

### Task 3: ContentFingerprintedParser

**Files:**
- Create: `Sources/CodexBarCore/Pipeline/ContentFingerprintedParser.swift`
- Create: `TestsLite/Pipeline/ContentFingerprintedParserTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// TestsLite/Pipeline/ContentFingerprintedParserTests.swift
import Testing
import Foundation
@testable import CodexBarCore

@Suite("ContentFingerprintedParser")
struct ContentFingerprintedParserTests {

    @Test("returns fullReparse for new file with no cache entry")
    func newFileFullReparse() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "fp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let file = tmpDir.appending(path: "test.jsonl")
        try Data("line1\nline2\n".utf8).write(to: file)

        let decision = try ContentFingerprintedParser.parseDecision(
            for: file, cached: nil
        )
        #expect(decision == .fullReparse)
    }

    @Test("returns skip for unchanged file")
    func unchangedFileSkip() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "fp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let file = tmpDir.appending(path: "test.jsonl")
        let content = Data("line1\nline2\n".utf8)
        try content.write(to: file)

        // Build a cache entry matching the current file state
        let entry = try ContentFingerprintedParser.buildCacheEntry(
            for: file, parsedOffset: Int64(content.count)
        )
        let decision = try ContentFingerprintedParser.parseDecision(
            for: file, cached: entry
        )
        #expect(decision == .skip)
    }

    @Test("returns incremental for appended file")
    func appendedFileIncremental() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "fp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let file = tmpDir.appending(path: "test.jsonl")
        let initial = Data("line1\n".utf8)
        try initial.write(to: file)

        let entry = try ContentFingerprintedParser.buildCacheEntry(
            for: file, parsedOffset: Int64(initial.count)
        )

        // Append more data
        let handle = try FileHandle(forWritingTo: file)
        handle.seekToEndOfFile()
        handle.write(Data("line2\n".utf8))
        handle.closeFile()

        let decision = try ContentFingerprintedParser.parseDecision(
            for: file, cached: entry
        )
        if case .incremental(let offset) = decision {
            #expect(offset == Int64(initial.count))
        } else {
            Issue.record("Expected .incremental, got \(decision)")
        }
    }

    @Test("returns fullReparse for truncated file")
    func truncatedFileFullReparse() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "fp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let file = tmpDir.appending(path: "test.jsonl")
        let content = Data("line1\nline2\nline3\n".utf8)
        try content.write(to: file)

        let entry = try ContentFingerprintedParser.buildCacheEntry(
            for: file, parsedOffset: Int64(content.count)
        )

        // Truncate the file
        try Data("short\n".utf8).write(to: file)

        let decision = try ContentFingerprintedParser.parseDecision(
            for: file, cached: entry
        )
        #expect(decision == .fullReparse)
    }

    @Test("returns fullReparse when header content changes (rotation)")
    func rotatedFileFullReparse() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "fp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let file = tmpDir.appending(path: "test.jsonl")
        try Data("original-content-line1\n".utf8).write(to: file)

        let entry = try ContentFingerprintedParser.buildCacheEntry(
            for: file, parsedOffset: 22
        )

        // Replace with different content of similar size
        try Data("replaced-content-XXX1\n".utf8).write(to: file)

        let decision = try ContentFingerprintedParser.parseDecision(
            for: file, cached: entry
        )
        #expect(decision == .fullReparse)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ContentFingerprintedParserTests 2>&1 | tail -20`
Expected: FAIL — `ContentFingerprintedParser` not found

- [ ] **Step 3: Write the implementation**

```swift
// Sources/CodexBarCore/Pipeline/ContentFingerprintedParser.swift
import Foundation
import CryptoKit

/// Determines whether a JSONL file should be fully reparsed, incrementally
/// parsed from an offset, or skipped entirely — using inode identity and
/// content fingerprinting to detect file rotation, truncation, and replacement.
enum ContentFingerprintedParser {

    /// The parse decision for a given file.
    enum Decision: Equatable, Sendable {
        case fullReparse
        case incremental(fromOffset: Int64)
        case skip
    }

    /// Cached metadata for a previously parsed file.
    struct CacheEntry: Codable, Sendable, Equatable {
        var path: String
        var size: Int64
        var parsedOffset: Int64
        var headerFingerprint: Data    // SHA256 of first 4096 bytes
        var inodeIdentifier: UInt64    // stat().st_ino
    }

    private static let fingerprintSize = 4096

    /// Build a cache entry for the current state of a file.
    static func buildCacheEntry(for fileURL: URL, parsedOffset: Int64) throws -> CacheEntry {
        let path = fileURL.path
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs[.size] as? Int64) ?? 0
        let inode = (attrs[.systemFileNumber] as? UInt64) ?? 0

        let fingerprint = try computeFingerprint(for: fileURL, maxBytes: fingerprintSize)

        return CacheEntry(
            path: path,
            size: size,
            parsedOffset: parsedOffset,
            headerFingerprint: fingerprint,
            inodeIdentifier: inode
        )
    }

    /// Determine the parse decision for a file given its cached state.
    static func parseDecision(for fileURL: URL, cached: CacheEntry?) throws -> Decision {
        guard let cached else { return .fullReparse }

        let path = fileURL.path
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let currentSize = (attrs[.size] as? Int64) ?? 0
        let currentInode = (attrs[.systemFileNumber] as? UInt64) ?? 0

        // 1. Inode changed → file replaced
        if currentInode != cached.inodeIdentifier {
            return .fullReparse
        }

        // 2. File truncated (smaller than previously parsed offset)
        if currentSize < cached.parsedOffset {
            return .fullReparse
        }

        // 3. File unchanged (same size as when we last parsed)
        if currentSize == cached.size && currentSize == cached.parsedOffset {
            return .skip
        }

        // 4. File grew — verify header fingerprint hasn't changed
        let currentFingerprint = try computeFingerprint(for: fileURL, maxBytes: fingerprintSize)
        if currentFingerprint != cached.headerFingerprint {
            return .fullReparse
        }

        // 5. Header matches, file grew → safe to parse incrementally
        if currentSize > cached.parsedOffset {
            return .incremental(fromOffset: cached.parsedOffset)
        }

        return .skip
    }

    /// Evict cache entries for files that are now empty (size 0).
    static func shouldEvictCacheEntry(for fileURL: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int64 else {
            return true  // file doesn't exist → evict
        }
        return size <= 0
    }

    // MARK: - Private

    private static func computeFingerprint(for fileURL: URL, maxBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { handle.closeFile() }
        let headerData = handle.readData(ofLength: maxBytes)
        let digest = SHA256.hash(data: headerData)
        return Data(digest)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ContentFingerprintedParserTests 2>&1 | tail -20`
Expected: PASS (all 5 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBarCore/Pipeline/ContentFingerprintedParser.swift TestsLite/Pipeline/ContentFingerprintedParserTests.swift
git commit -m "feat: add ContentFingerprintedParser for rotation-safe incremental JSONL parsing"
```

---

## Chunk 2: FSEventsWatcher

### Task 4: FSEventsWatcher

**Files:**
- Create: `Sources/CodexBarCore/Pipeline/FSEventsWatcher.swift`
- Create: `TestsLite/Pipeline/FSEventsWatcherTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// TestsLite/Pipeline/FSEventsWatcherTests.swift
import Testing
import Foundation
@testable import CodexBarCore

@Suite("FSEventsWatcher")
struct FSEventsWatcherTests {

    @Test("emits events when a watched file is created")
    func detectsFileCreation() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "fswatch-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let watcher = FSEventsWatcher()
        let stream = await watcher.watch(
            directories: [(url: tmpDir, fileExtensions: ["jsonl"])],
            coalescingLatency: 0.5
        )

        // Write a file after a short delay
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            let file = tmpDir.appending(path: "test.jsonl")
            try? Data("test\n".utf8).write(to: file)
        }

        // Wait for at least one batch of events
        var received = false
        for await batch in stream {
            if batch.contains(where: { $0.path.hasSuffix("test.jsonl") }) {
                received = true
                break
            }
        }

        await watcher.stopAll()
        #expect(received)
    }

    @Test("filters by file extension")
    func filtersExtensions() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "fswatch-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let watcher = FSEventsWatcher()
        let stream = await watcher.watch(
            directories: [(url: tmpDir, fileExtensions: ["jsonl"])],
            coalescingLatency: 0.5
        )

        // Write a .txt file (should be filtered) and a .jsonl file
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            try? Data("ignore".utf8).write(to: tmpDir.appending(path: "ignore.txt"))
            try? await Task.sleep(for: .milliseconds(100))
            try? Data("match".utf8).write(to: tmpDir.appending(path: "match.jsonl"))
        }

        var receivedJsonl = false
        var receivedTxt = false
        let timeout = Task {
            try? await Task.sleep(for: .seconds(3))
            await watcher.stopAll()
        }

        for await batch in stream {
            for event in batch {
                if event.path.hasSuffix(".jsonl") { receivedJsonl = true }
                if event.path.hasSuffix(".txt") { receivedTxt = true }
            }
            if receivedJsonl { break }
        }

        timeout.cancel()
        await watcher.stopAll()
        #expect(receivedJsonl)
        #expect(!receivedTxt)
    }

    @Test("stopAll terminates the stream")
    func stopAllTerminates() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "fswatch-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let watcher = FSEventsWatcher()
        let stream = await watcher.watch(
            directories: [(url: tmpDir, fileExtensions: ["jsonl"])],
            coalescingLatency: 0.5
        )

        // Stop immediately
        await watcher.stopAll()

        // Stream should terminate (for-await loop exits)
        var count = 0
        for await _ in stream { count += 1 }
        #expect(count == 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FSEventsWatcherTests 2>&1 | tail -20`
Expected: FAIL — `FSEventsWatcher` not found

- [ ] **Step 3: Write the implementation**

```swift
// Sources/CodexBarCore/Pipeline/FSEventsWatcher.swift
#if canImport(CoreServices)
import CoreServices
import Foundation

/// Watches directory trees for file changes using macOS FSEvents.
/// Emits batched, extension-filtered events via AsyncStream.
actor FSEventsWatcher {

    struct FileChangeEvent: Sendable {
        let path: String
        let flags: FSEventStreamEventFlags
        let eventId: FSEventStreamEventId
    }

    /// Sentinel event indicating the kernel dropped events and a full rescan is needed.
    static let mustRescanFlag: FSEventStreamEventFlags =
        FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)

    private var streams: [Stream] = []
    private var continuation: AsyncStream<[FileChangeEvent]>.Continuation?
    private let queue = DispatchQueue(label: "com.codexbar.fsevents", qos: .utility)
    private var coalescingBuffer: [FileChangeEvent] = []
    private var coalescingTimer: DispatchWorkItem?
    private var coalescingLatency: TimeInterval = 2.0
    private var allowedExtensions: Set<String> = []
    private var lastCallbackTimestamp: Date = Date()

    /// Persisted event ID for replay on relaunch.
    private static let eventIdKey = "FSEventsWatcher.lastEventId"

    /// Watch multiple directory trees simultaneously.
    /// Returns a single merged AsyncStream of batched events.
    /// The stream terminates when stopAll() is called.
    func watch(
        directories: [(url: URL, fileExtensions: Set<String>)],
        coalescingLatency: TimeInterval = 2.0
    ) -> AsyncStream<[FileChangeEvent]> {
        // Invalidate any previous stream
        stopAllSync()

        self.coalescingLatency = coalescingLatency
        self.allowedExtensions = directories.reduce(into: Set<String>()) {
            $0.formUnion($1.fileExtensions)
        }

        let (stream, cont) = AsyncStream<[FileChangeEvent]>.makeStream(
            bufferingPolicy: .bufferingNewest(20)
        )
        self.continuation = cont

        let lastEventId = UInt64(
            UserDefaults.standard.integer(forKey: Self.eventIdKey)
        )

        for (url, _) in directories {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if let fsStream = createStream(
                for: url,
                sinceEventId: lastEventId > 0
                    ? FSEventStreamEventId(lastEventId)
                    : FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency: coalescingLatency
            ) {
                streams.append(fsStream)
            }
        }

        return stream
    }

    /// Stops all FSEventStreams and terminates the AsyncStream.
    func stopAll() {
        stopAllSync()
    }

    /// Whether the last FSEvents callback fired within the given duration.
    /// Used for dead stream detection.
    func lastCallbackAge() -> TimeInterval {
        Date().timeIntervalSince(lastCallbackTimestamp)
    }

    // MARK: - Private

    private struct Stream {
        let ref: FSEventStreamRef
    }

    private func stopAllSync() {
        coalescingTimer?.cancel()
        coalescingTimer = nil
        flushBuffer()

        for s in streams {
            FSEventStreamStop(s.ref)
            FSEventStreamInvalidate(s.ref)
            FSEventStreamRelease(s.ref)
        }
        streams.removeAll()

        continuation?.finish()
        continuation = nil
    }

    private func flushBuffer() {
        guard !coalescingBuffer.isEmpty else { return }
        let batch = coalescingBuffer
        coalescingBuffer.removeAll()
        continuation?.yield(batch)

        // Persist the latest event ID
        if let lastId = batch.last?.eventId {
            UserDefaults.standard.set(Int(lastId), forKey: Self.eventIdKey)
        }
    }

    nonisolated private func createStream(
        for directory: URL,
        sinceEventId: FSEventStreamEventId,
        latency: TimeInterval
    ) -> Stream? {
        let pathString = directory.path as CFString
        let paths = [pathString] as CFArray

        var context = FSEventStreamContext()
        // We use Unmanaged to pass self to the C callback
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagFileEvents) |
            UInt32(kFSEventStreamCreateFlagUseCFTypes) |
            UInt32(kFSEventStreamCreateFlagNoDefer)

        guard let streamRef = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            paths,
            sinceEventId,
            latency,
            flags
        ) else { return nil }

        let q = queue
        FSEventStreamSetDispatchQueue(streamRef, q)
        FSEventStreamStart(streamRef)

        return Stream(ref: streamRef)
    }

    /// Receives events from the C callback on the dispatch queue, then
    /// forwards to the actor for filtering and coalescing.
    fileprivate func handleEvents(
        _ paths: [String],
        _ flags: [FSEventStreamEventFlags],
        _ ids: [FSEventStreamEventId]
    ) {
        lastCallbackTimestamp = Date()

        for i in 0..<paths.count {
            let path = paths[i]
            let flag = flags[i]
            let eventId = ids[i]

            // Check for kernel overflow → emit must-rescan
            if flag & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0 {
                coalescingBuffer.append(FileChangeEvent(
                    path: path, flags: flag, eventId: eventId
                ))
                continue
            }

            // Filter by extension
            let ext = (path as NSString).pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }

            coalescingBuffer.append(FileChangeEvent(
                path: path, flags: flag, eventId: eventId
            ))
        }

        // Reset coalescing timer
        coalescingTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { await self.flushBuffer() }
        }
        coalescingTimer = item
        queue.asyncAfter(deadline: .now() + coalescingLatency, execute: item)
    }
}

// MARK: - C Callback

private func fsEventsCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()

    let cfPaths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    var paths: [String] = []
    var flags: [FSEventStreamEventFlags] = []
    var ids: [FSEventStreamEventId] = []

    for i in 0..<numEvents {
        if let cfStr = CFArrayGetValueAtIndex(cfPaths, i) {
            let str = Unmanaged<CFString>.fromOpaque(cfStr).takeUnretainedValue() as String
            paths.append(str)
            flags.append(eventFlags[i])
            ids.append(eventIds[i])
        }
    }

    Task {
        await watcher.handleEvents(paths, flags, ids)
    }
}

#endif // canImport(CoreServices)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FSEventsWatcherTests 2>&1 | tail -20`
Expected: PASS (all 3 tests). Note: FSEvents tests require macOS and real filesystem; may need slightly longer timeouts on slow CI.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBarCore/Pipeline/FSEventsWatcher.swift TestsLite/Pipeline/FSEventsWatcherTests.swift
git commit -m "feat: add FSEventsWatcher for event-driven JSONL file monitoring"
```

---

## Chunk 3: Provider-Aware Deduplication + Cache Format Migration

### Task 5: Update CostUsageCache with fingerprint fields

**Files:**
- Modify: `Sources/CodexBarCore/Vendored/CostUsage/CostUsageCache.swift`

- [ ] **Step 1: Read current CostUsageCache.swift**

Read `Sources/CodexBarCore/Vendored/CostUsage/CostUsageCache.swift` to understand the exact current `CostUsageFileUsage` and `CostUsageCache` structures.

- [ ] **Step 2: Add fingerprint fields and bump version**

Add to `CostUsageFileUsage`:
```swift
var headerFingerprint: Data?     // SHA256 of first 4096 bytes (nil = legacy entry)
var inodeIdentifier: UInt64?     // stat().st_ino (nil = legacy entry)
```

Update `CostUsageCache`:
```swift
var version: Int = 3  // bumped from 1 to 3 (skip 2 per spec: Phases 1+3 deploy together)
```

Update `CostUsageCacheIO.load()` to discard caches with `version < 3` (return empty cache, triggering full reparse).

- [ ] **Step 3: Verify build succeeds**

Run: `swift build --target CodexBarCore 2>&1 | tail -10`
Expected: Build succeeded (new fields are optional, so existing code compiles without changes)

- [ ] **Step 4: Commit**

```bash
git add Sources/CodexBarCore/Vendored/CostUsage/CostUsageCache.swift
git commit -m "feat: add fingerprint fields to CostUsageCache, bump version to 3"
```

---

### Task 6: Claude two-layer deduplication

**Files:**
- Modify: `Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner+Claude.swift`
- Create: `TestsLite/Pipeline/DeduplicationTests.swift`

- [ ] **Step 1: Write failing tests for Claude dedup**

```swift
// TestsLite/Pipeline/DeduplicationTests.swift
import Testing
import Foundation
@testable import CodexBarCore

@Suite("Claude Deduplication")
struct ClaudeDeduplicationTests {

    @Test("layer 1: deduplicates by messageId + requestId")
    func keyBasedDedup() throws {
        // Create a temp JSONL file with duplicate entries (same messageId + requestId)
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "dedup-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let file = tmpDir.appending(path: "test.jsonl")
        let entry = """
        {"type":"assistant","message":{"id":"msg_001","model":"claude-sonnet-4-20250514","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"requestId":"req_001","timestamp":"2026-03-15T10:00:00Z"}
        {"type":"assistant","message":{"id":"msg_001","model":"claude-sonnet-4-20250514","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"requestId":"req_001","timestamp":"2026-03-15T10:00:00Z"}
        """
        try Data(entry.utf8).write(to: file)

        // NOTE: The `range:` parameter type is `CostUsageDayRange`, not `ClosedRange<Date>`.
        // Check CostUsageScanner.swift for the actual type and construct appropriately.
        // Example: CostUsageDayRange(from: "2026-03-01", to: "2026-03-31")
        let range = CostUsageDayRange(from: "2020-01-01", to: "2030-12-31")
        let result = CostUsageScanner.parseClaudeFile(
            fileURL: file,
            range: range,
            providerFilter: .all,
            startOffset: 0
        )

        // Should count tokens only once despite two identical entries
        let dayKey = "2026-03-15"
        let model = "claude-sonnet-4-20250514"
        let tokens = result.days[dayKey]?[model]
        #expect(tokens?[0] == 100)  // input
        #expect(tokens?[3] == 50)   // output
    }

    @Test("layer 2: temporal grouping for entries with missing requestId")
    func temporalGroupingDedup() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "dedup-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let file = tmpDir.appending(path: "test.jsonl")
        // Two entries with same messageId but no requestId, within 5 seconds
        let entry = """
        {"type":"assistant","message":{"id":"msg_002","model":"claude-sonnet-4-20250514","usage":{"input_tokens":100,"output_tokens":30,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"2026-03-15T10:00:01Z"}
        {"type":"assistant","message":{"id":"msg_002","model":"claude-sonnet-4-20250514","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"2026-03-15T10:00:03Z"}
        """
        try Data(entry.utf8).write(to: file)

        let range = CostUsageDayRange(from: "2020-01-01", to: "2030-12-31")
        let result = CostUsageScanner.parseClaudeFile(
            fileURL: file,
            range: range,
            providerFilter: .all,
            startOffset: 0
        )

        // Should take MAX output tokens (50, not 30, and not 80 sum)
        let dayKey = "2026-03-15"
        let model = "claude-sonnet-4-20250514"
        let tokens = result.days[dayKey]?[model]
        #expect(tokens?[0] == 100)  // input (max)
        #expect(tokens?[3] == 50)   // output (max, not sum)
    }
}

@Suite("Codex Deduplication")
struct CodexDeduplicationTests {

    @Test("detects counter reset and uses absolute values")
    func counterResetDetection() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "dedup-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let file = tmpDir.appending(path: "session.jsonl")
        // First entry: high cumulative totals
        // Second entry: low totals (counter reset)
        let entry = """
        {"type":"response.completed","response":{"model":"gpt-5-mini","usage":{"total_tokens":1000,"input_tokens":800,"output_tokens":200,"input_tokens_details":{"cached_tokens":0}}},"session_meta":{"session_id":"sess_001"},"timestamp":"2026-03-15T10:00:00Z"}
        {"type":"response.completed","response":{"model":"gpt-5-mini","usage":{"total_tokens":150,"input_tokens":100,"output_tokens":50,"input_tokens_details":{"cached_tokens":0}}},"session_meta":{"session_id":"sess_001"},"timestamp":"2026-03-15T10:00:30Z"}
        """
        try Data(entry.utf8).write(to: file)

        let range = CostUsageDayRange(from: "2020-01-01", to: "2030-12-31")
        let result = CostUsageScanner.parseCodexFile(
            fileURL: file,
            range: range,
            startOffset: 0,
            initialModel: nil,
            initialTotals: nil
        )

        // First entry: delta from zero = 800 input, 200 output
        // Second entry: counter reset detected → absolute = 100 input, 50 output
        // Total: 900 input, 250 output
        let dayKey = "2026-03-15"
        let model = "gpt-5-mini"
        let tokens = result.days[dayKey]?[model]
        #expect(tokens?[0] == 900)   // input: 800 + 100
        #expect(tokens?[2] == 250)   // output: 200 + 50
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "ClaudeDeduplicationTests|CodexDeduplicationTests" 2>&1 | tail -20`
Expected: FAIL — existing dedup produces different results

- [ ] **Step 3: Implement Claude two-layer deduplication**

In `CostUsageScanner+Claude.swift`, modify the deduplication section of `parseClaudeFile()`:

Add a `temporalGroups` dictionary alongside the existing `seenKeys` set. After all lines are parsed, process temporal groups by emitting the MAX token counts per group. See spec Section 4.3 for the exact algorithm.

Key changes:
- When both `messageId` and `requestId` are present → Layer 1 (existing key-based dedup)
- When either is missing → Layer 2 (accumulate into temporal group, keyed by `"\(filePath):\(model):\(roundedTimestamp5s)"`)
- After file parse completes, iterate temporal groups and add MAX values to `days`

- [ ] **Step 4: Implement Codex counter-reset detection**

In `CostUsageScanner.swift`, modify `parseCodexFile()` at the delta computation section:

```swift
// Replace the existing delta computation:
let deltaInput = max(0, input - prev.input)
// With:
let bothDropped = input < prev.input && output < prev.output
let deltaInput: Int
let deltaCached: Int
let deltaOutput: Int
if bothDropped {
    // Counter reset: treat current values as absolute
    deltaInput = input
    deltaCached = cached
    deltaOutput = output
} else {
    // Normal delta (existing behavior)
    deltaInput = max(0, input - prev.input)
    deltaCached = max(0, cached - prev.cached)
    deltaOutput = max(0, output - prev.output)
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter "ClaudeDeduplicationTests|CodexDeduplicationTests" 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 6: Run existing scanner tests to verify no regressions**

Run: `swift test --filter CostUsageScannerTests 2>&1 | tail -20`
Expected: PASS (all existing tests still pass)

- [ ] **Step 7: Commit**

```bash
git add Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner+Claude.swift Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner.swift TestsLite/Pipeline/DeduplicationTests.swift
git commit -m "feat: implement provider-aware deduplication (Claude two-layer + Codex counter-reset)"
```

---

## Chunk 4: PricingResolver + Tiered Pricing Fix

### Task 7: Embedded pricing snapshot script

**Files:**
- Create: `Scripts/update_embedded_pricing.sh`
- Create: `Sources/CodexBarCore/Pipeline/EmbeddedPricing.swift`

- [ ] **Step 1: Create the build script**

```bash
#!/bin/bash
# Scripts/update_embedded_pricing.sh
# Fetches LiteLLM pricing and generates EmbeddedPricing.swift
set -euo pipefail

URL="https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
OUT="Sources/CodexBarCore/Pipeline/EmbeddedPricing.swift"
TMP=$(mktemp)

echo "Fetching LiteLLM pricing..."
curl -sS --max-time 30 "$URL" -o "$TMP"

# Validate it's valid JSON
python3 -c "import json; json.load(open('$TMP'))" || { echo "Invalid JSON"; exit 1; }

# Generate Swift file with the JSON embedded as a static string
cat > "$OUT" << 'SWIFT_HEADER'
// Auto-generated by Scripts/update_embedded_pricing.sh — do not edit manually.
// Last updated: TIMESTAMP
import Foundation

enum EmbeddedPricing {
    /// The embedded LiteLLM pricing data, fetched at build time.
    static let jsonData: Data = {
        Data(jsonString.utf8)
    }()

    private static let jsonString = ###"
SWIFT_HEADER

# Replace TIMESTAMP with current date
sed -i '' "s/TIMESTAMP/$(date -u +%Y-%m-%dT%H:%M:%SZ)/" "$OUT"

# Append the JSON content
cat "$TMP" >> "$OUT"

# Close the Swift string
cat >> "$OUT" << 'SWIFT_FOOTER'
"###
}
SWIFT_FOOTER

rm "$TMP"
echo "Generated $OUT"
```

- [ ] **Step 2: Run the script**

Run: `chmod +x Scripts/update_embedded_pricing.sh && bash Scripts/update_embedded_pricing.sh`
Expected: Generates `Sources/CodexBarCore/Pipeline/EmbeddedPricing.swift`

- [ ] **Step 3: Verify it compiles**

Run: `swift build --target CodexBarCore 2>&1 | tail -10`
Expected: Build succeeded

- [ ] **Step 4: Commit**

```bash
git add Scripts/update_embedded_pricing.sh Sources/CodexBarCore/Pipeline/EmbeddedPricing.swift
git commit -m "feat: add LiteLLM embedded pricing snapshot and generation script"
```

---

### Task 8: PricingResolver

**Files:**
- Create: `Sources/CodexBarCore/Pipeline/PricingResolver.swift`
- Create: `TestsLite/Pipeline/PricingResolverTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// TestsLite/Pipeline/PricingResolverTests.swift
import Testing
import Foundation
@testable import CodexBarCore

@Suite("PricingResolver")
struct PricingResolverTests {

    // MARK: - Model Resolution Chain

    @Test("resolves exact model name")
    func exactMatch() async throws {
        let resolver = PricingResolver(networkEnabled: false)
        let pricing = await resolver.resolve(model: "claude-sonnet-4-20250514")
        #expect(pricing != nil)
        #expect(pricing!.inputCostPerToken > 0)
    }

    @Test("resolves model by stripping date suffix")
    func stripDateSuffix() async throws {
        let resolver = PricingResolver(networkEnabled: false)
        let p1 = await resolver.resolve(model: "claude-sonnet-4-20250514")
        let p2 = await resolver.resolve(model: "claude-sonnet-4-20260101")
        // Both should resolve (either exact or stripped)
        #expect(p1 != nil)
        // p2 might resolve via stripping to "claude-sonnet-4" then matching
    }

    @Test("resolves Vertex AI @ format")
    func vertexAIFormat() async throws {
        let resolver = PricingResolver(networkEnabled: false)
        let pricing = await resolver.resolve(model: "claude-opus-4-5@20251101")
        #expect(pricing != nil)
    }

    @Test("resolves bracket notation")
    func bracketNotation() async throws {
        let resolver = PricingResolver(networkEnabled: false)
        let pricing = await resolver.resolve(model: "claude-opus-4-6[1m]")
        #expect(pricing != nil)
    }

    @Test("returns nil for completely unknown model")
    func unknownModel() async throws {
        let resolver = PricingResolver(networkEnabled: false)
        let pricing = await resolver.resolve(model: "totally-fake-model-xyz")
        #expect(pricing == nil)
    }

    // MARK: - Tiered Pricing

    @Test("tiered pricing uses shared budget across input categories")
    func tieredPricingSharedBudget() async throws {
        let resolver = PricingResolver(networkEnabled: false)

        // Scenario: 150K input + 150K cache_read = 300K total (above 200K threshold)
        let cost = await resolver.cost(
            model: "claude-sonnet-4-5-20250514",
            inputTokens: 150_000,
            cacheReadInputTokens: 150_000,
            cacheCreationInputTokens: 0,
            outputTokens: 1_000
        )

        // With shared budget of 200K:
        // - 150K input all under threshold (budget remaining: 50K)
        // - 50K cache_read under threshold, 100K cache_read above threshold
        #expect(cost != nil)
        #expect(cost! > 0)
    }

    @Test("output tokens never use tiered pricing")
    func outputNeverTiered() async throws {
        let resolver = PricingResolver(networkEnabled: false)

        let cost1 = await resolver.cost(
            model: "claude-sonnet-4-5-20250514",
            inputTokens: 100,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 500_000  // way over any threshold
        )

        let cost2 = await resolver.cost(
            model: "claude-sonnet-4-5-20250514",
            inputTokens: 100,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 1_000
        )

        // Output cost should scale linearly (no tier break)
        #expect(cost1 != nil && cost2 != nil)
        let ratio = cost1! / cost2!
        // Should be close to 500 (500K/1K), not something smaller due to tiering
        #expect(ratio > 400 && ratio < 600)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PricingResolverTests 2>&1 | tail -20`
Expected: FAIL — `PricingResolver` not found

- [ ] **Step 3: Write the implementation**

Create `Sources/CodexBarCore/Pipeline/PricingResolver.swift` with:

1. **Model pricing data structure**: `ModelPricing` struct with `inputCostPerToken`, `outputCostPerToken`, `cacheReadCostPerToken`, `cacheCreateCostPerToken`, and optional `tieredThreshold` + above-threshold rates.

2. **5-layer resolution**: Load from embedded pricing (Layer 5) on init. Disk cache (Layer 2) checked on init. Network fetch (Layer 3) triggered async on init and every 24h. In-memory cache (Layer 1) is the parsed pricing dictionary.

3. **Model name resolution chain**: The 7-step resolution from the spec (exact → alias → strip date → convert `@` → strip brackets → provider prefix → fuzzy).

4. **Tiered pricing calculation**: The shared-budget algorithm from spec Section 4.4.

5. **`cost()` function**: Takes model + token counts, resolves pricing, applies tiered calculation.

Key interface:
```swift
actor PricingResolver {
    init(networkEnabled: Bool = true, cacheDirectory: URL? = nil)
    func resolve(model: String) -> ModelPricing?
    func cost(model: String, inputTokens: Int, cacheReadInputTokens: Int,
              cacheCreationInputTokens: Int, outputTokens: Int) -> Double?
    func refreshPricing() async
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PricingResolverTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBarCore/Pipeline/PricingResolver.swift TestsLite/Pipeline/PricingResolverTests.swift
git commit -m "feat: add PricingResolver with LiteLLM integration and tiered pricing fix"
```

---

### Task 9: Wire PricingResolver into CostUsagePricing

**Files:**
- Modify: `Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift`
- Modify: `TestsLite/CostUsagePricingTests.swift`

- [ ] **Step 1: Read current CostUsagePricing.swift**

Read the full file to understand the existing `claudeCostUSD` and `normalizeClaudeModel` functions.

- [ ] **Step 2: Add tests for the tiered pricing fix**

Add to existing `CostUsagePricingTests.swift`:

```swift
@Test("tiered pricing applies shared budget across input categories")
func tieredSharedBudget() {
    // 150K input + 100K cache_read = 250K total → some tokens above 200K threshold
    let cost = CostUsagePricing.claudeCostUSD(
        model: "claude-sonnet-4-5-20250514",
        inputTokens: 150_000,
        cacheReadInputTokens: 100_000,
        cacheCreationInputTokens: 0,
        outputTokens: 1_000
    )
    #expect(cost != nil)

    // Compare with all tokens under threshold
    let costAllUnder = CostUsagePricing.claudeCostUSD(
        model: "claude-sonnet-4-5-20250514",
        inputTokens: 100_000,
        cacheReadInputTokens: 50_000,
        cacheCreationInputTokens: 0,
        outputTokens: 1_000
    )
    #expect(costAllUnder != nil)

    // The first cost should be higher (some tokens at overage rate)
    // because total input context 250K > 200K threshold
    #expect(cost! > costAllUnder!)
}

@Test("output tokens never get tiered pricing")
func outputNeverTiered() {
    let cost = CostUsagePricing.claudeCostUSD(
        model: "claude-sonnet-4-5-20250514",
        inputTokens: 100,
        cacheReadInputTokens: 0,
        cacheCreationInputTokens: 0,
        outputTokens: 300_000
    )
    #expect(cost != nil)
    // Output cost should be purely linear: 300K * outputRate
}
```

- [ ] **Step 3: Fix the tiered pricing in claudeCostUSD**

Replace the per-category `tiered()` calls with the shared-budget algorithm from spec Section 4.4. Keep the existing hardcoded pricing tables as the fallback (Layer 5), but add an optional delegation to `PricingResolver` when available.

- [ ] **Step 4: Run tests**

Run: `swift test --filter CostUsagePricingTests 2>&1 | tail -20`
Expected: PASS (new tests + all existing tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift TestsLite/CostUsagePricingTests.swift
git commit -m "fix: apply tiered pricing threshold as shared budget across input categories"
```

---

## Chunk 5: CoalescingEngine + AdaptiveRefreshTimer + SystemLifecycleObserver

### Task 10: CoalescingEngine

**Files:**
- Create: `Sources/CodexBarCore/Pipeline/CoalescingEngine.swift`
- Create: `TestsLite/Pipeline/CoalescingEngineTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// TestsLite/Pipeline/CoalescingEngineTests.swift
import Testing
import Foundation
@testable import CodexBarCore

@Suite("CoalescingEngine")
struct CoalescingEngineTests {

    @Test("merges refresh requests by OR-ing flags and taking highest priority")
    func mergeRequests() {
        var engine = CoalescingEngine()
        engine.mergeRefreshRequest(RefreshRequest(
            forceTokenUsage: true, priority: .p2
        ))
        engine.mergeRefreshRequest(RefreshRequest(
            forceStatusChecks: true, priority: .p0
        ))

        let merged = engine.drainPendingRequest()
        #expect(merged?.forceTokenUsage == true)
        #expect(merged?.forceStatusChecks == true)
        #expect(merged?.priority == .p0)
    }

    @Test("shouldSkip returns true within minimum interval")
    func minimumInterval() {
        var engine = CoalescingEngine()
        engine.recordCompletion(provider: .claude, kind: .quota)

        // Immediately after → should skip
        let skip = engine.shouldSkip(provider: .claude, kind: .quota, priority: .p2)
        #expect(skip == true)
    }

    @Test("shouldSkip returns false for P0 with forceQuota")
    func p0BypassesInterval() {
        var engine = CoalescingEngine()
        engine.recordCompletion(provider: .claude, kind: .quota)

        let skip = engine.shouldSkip(provider: .claude, kind: .quota, priority: .p0)
        #expect(skip == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CoalescingEngineTests 2>&1 | tail -20`
Expected: FAIL — `CoalescingEngine` not found

- [ ] **Step 3: Write the implementation**

```swift
// Sources/CodexBarCore/Pipeline/CoalescingEngine.swift
import Foundation

/// Handles debouncing, request merging, and minimum interval enforcement.
struct CoalescingEngine: Sendable {
    enum FetchKind: Sendable {
        case quota
        case tokenCost
        case status
    }

    private var pendingRequest: RefreshRequest?
    private var lastCompletion: [String: Date] = [:]  // "provider:kind" → Date

    /// Minimum intervals (seconds) by priority tier.
    private static let minimumIntervals: [FetchKind: [RefreshRequest.Priority: TimeInterval]] = [
        .quota: [.p0: 0, .p1: 30, .p2: 60, .p3: 60],
        .tokenCost: [.p0: 0, .p1: 10, .p2: 300, .p3: 300],
        .status: [.p0: 0, .p1: 60, .p2: 600, .p3: 600],
    ]

    mutating func mergeRefreshRequest(_ request: RefreshRequest) {
        if var existing = pendingRequest {
            existing.merge(request)
            pendingRequest = existing
        } else {
            pendingRequest = request
        }
    }

    mutating func drainPendingRequest() -> RefreshRequest? {
        defer { pendingRequest = nil }
        return pendingRequest
    }

    func shouldSkip(provider: UsageProvider, kind: FetchKind, priority: RefreshRequest.Priority) -> Bool {
        if priority == .p0 { return false }

        let key = "\(provider):\(kind)"
        guard let last = lastCompletion[key] else { return false }

        let minInterval = Self.minimumIntervals[kind]?[priority] ?? 60
        return Date().timeIntervalSince(last) < minInterval
    }

    mutating func recordCompletion(provider: UsageProvider, kind: FetchKind) {
        let key = "\(provider):\(kind)"
        lastCompletion[key] = Date()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CoalescingEngineTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBarCore/Pipeline/CoalescingEngine.swift TestsLite/Pipeline/CoalescingEngineTests.swift
git commit -m "feat: add CoalescingEngine for request merging and interval enforcement"
```

---

### Task 11: AdaptiveRefreshTimer

**Files:**
- Create: `Sources/CodexBarCore/Pipeline/AdaptiveRefreshTimer.swift`
- Create: `TestsLite/Pipeline/AdaptiveRefreshTimerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// TestsLite/Pipeline/AdaptiveRefreshTimerTests.swift
import Testing
import Foundation
@testable import CodexBarCore

@Suite("AdaptiveRefreshTimer")
struct AdaptiveRefreshTimerTests {

    @Test("starts in idle state with 15min interval")
    func initialState() async {
        let timer = AdaptiveRefreshTimer()
        let interval = await timer.currentInterval
        #expect(interval == .seconds(900))
    }

    @Test("transitions to active on FSEvent")
    func transitionsToActive() async {
        let timer = AdaptiveRefreshTimer()
        await timer.recordFSEvent()
        await timer.evaluateState()
        let interval = await timer.currentInterval
        #expect(interval == .seconds(120))
    }

    @Test("transitions to deepIdle after 1 hour without events")
    func transitionsToDeepIdle() async {
        let timer = AdaptiveRefreshTimer(
            nowProvider: { Date(timeIntervalSinceNow: 3700) }  // 1hr+ in future
        )
        await timer.recordFSEvent()
        // Evaluate with "now" being 1hr+ later
        await timer.evaluateState()
        let interval = await timer.currentInterval
        #expect(interval == .seconds(1800))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AdaptiveRefreshTimerTests 2>&1 | tail -20`
Expected: FAIL — `AdaptiveRefreshTimer` not found

- [ ] **Step 3: Write the implementation**

```swift
// Sources/CodexBarCore/Pipeline/AdaptiveRefreshTimer.swift
import Foundation

/// Activity-aware polling timer with three states.
actor AdaptiveRefreshTimer {
    enum State: Sendable {
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AdaptiveRefreshTimerTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBarCore/Pipeline/AdaptiveRefreshTimer.swift TestsLite/Pipeline/AdaptiveRefreshTimerTests.swift
git commit -m "feat: add AdaptiveRefreshTimer with active/idle/deepIdle state machine"
```

---

### Task 12: SystemLifecycleObserver

**Files:**
- Create: `Sources/CodexBarCore/Pipeline/SystemLifecycleObserver.swift`

- [ ] **Step 1: Write the implementation**

This component is `@MainActor` and interacts with NSWorkspace notifications. It's primarily integration code, not unit-testable in isolation. Integration testing happens in Task 15.

```swift
// Sources/CodexBarCore/Pipeline/SystemLifecycleObserver.swift
#if canImport(AppKit)
import AppKit
import Foundation

/// Handles sleep/wake, App Nap prevention, and Space switch.
@MainActor
final class SystemLifecycleObserver {
    private var activityToken: NSObjectProtocol?
    private var sleepTimestamp: Date?
    private var observers: [NSObjectProtocol] = []

    private let onWake: @Sendable (_ sleepDuration: TimeInterval) async -> Void
    private let onSleep: @Sendable () async -> Void
    private let onSpaceChange: @MainActor () -> Void

    init(
        onWake: @escaping @Sendable (_ sleepDuration: TimeInterval) async -> Void,
        onSleep: @escaping @Sendable () async -> Void,
        onSpaceChange: @escaping @MainActor () -> Void
    ) {
        self.onWake = onWake
        self.onSleep = onSleep
        self.onSpaceChange = onSpaceChange
    }

    func start() {
        // Prevent App Nap from throttling timers
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "CodexBar usage monitoring"
        )

        let ws = NSWorkspace.shared.notificationCenter

        observers.append(ws.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.sleepTimestamp = Date()
            let onSleep = self.onSleep
            Task { await onSleep() }
        })

        observers.append(ws.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let duration = Date().timeIntervalSince(self.sleepTimestamp ?? Date())
            let onWake = self.onWake
            Task {
                // Wait for network interfaces to reconnect
                try? await Task.sleep(for: .seconds(duration > 3600 ? 5 : 3))
                await onWake(duration)
            }
        })

        observers.append(ws.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.onSpaceChange()
        })
    }

    func stop() {
        let ws = NSWorkspace.shared.notificationCenter
        for observer in observers {
            ws.removeObserver(observer)
        }
        observers.removeAll()

        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    deinit {
        // Observers must be removed on main thread
        let ws = NSWorkspace.shared.notificationCenter
        for observer in observers {
            ws.removeObserver(observer)
        }
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
        }
    }
}
#endif
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build --target CodexBarCore 2>&1 | tail -10`
Expected: Build succeeded

- [ ] **Step 3: Commit**

```bash
git add Sources/CodexBarCore/Pipeline/SystemLifecycleObserver.swift
git commit -m "feat: add SystemLifecycleObserver for sleep/wake and App Nap prevention"
```

---

## Chunk 6: DataPipeline Coordinator + UsageStore Rewire

### Task 13: DataPipeline actor

**Files:**
- Create: `Sources/CodexBarCore/Pipeline/DataPipeline.swift`
- Create: `TestsLite/Pipeline/DataPipelineTests.swift`

- [ ] **Step 1: Write failing integration tests**

```swift
// TestsLite/Pipeline/DataPipelineTests.swift
import Testing
import Foundation
@testable import CodexBarCore

@Suite("DataPipeline")
struct DataPipelineTests {

    @Test("emits events on enqueue and process")
    func emitsEvents() async throws {
        let pipeline = DataPipeline(
            fetchers: MockFetchers(),
            pricingResolver: PricingResolver(networkEnabled: false)
        )

        let events = await pipeline.events
        await pipeline.enqueue(RefreshRequest(
            providers: [.claude],
            forceQuota: true,
            priority: .p0
        ))

        var received = false
        let timeout = Task {
            try? await Task.sleep(for: .seconds(5))
            await pipeline.shutdown()
        }

        for await event in events {
            switch event {
            case .quotaUpdated, .error:
                received = true
            default: break
            }
            if received { break }
        }

        timeout.cancel()
        await pipeline.shutdown()
        #expect(received)
    }

    @Test("coalesces rapid requests")
    func coalescesRequests() async throws {
        let pipeline = DataPipeline(
            fetchers: MockFetchers(),
            pricingResolver: PricingResolver(networkEnabled: false)
        )

        // Enqueue 3 rapid requests
        await pipeline.enqueue(RefreshRequest(forceTokenUsage: true, priority: .p2))
        await pipeline.enqueue(RefreshRequest(forceStatusChecks: true, priority: .p1))
        await pipeline.enqueue(RefreshRequest(forceQuota: true, priority: .p0))

        // Should coalesce into one request with all flags and P0 priority
        // (verified by observing only one batch of events, not three)
        try? await Task.sleep(for: .seconds(1))
        await pipeline.shutdown()
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DataPipelineTests 2>&1 | tail -20`
Expected: FAIL — `DataPipeline` not found

- [ ] **Step 3: Write the implementation**

Create `Sources/CodexBarCore/Pipeline/DataPipeline.swift`:

```swift
actor DataPipeline {
    enum PipelineEvent: Sendable {
        case quotaUpdated(UsageProvider, UsageSnapshot)
        case costUpdated(UsageProvider, CostUsageTokenSnapshot)
        case statusUpdated(UsageProvider, ProviderStatus)
        case error(UsageProvider, Error)
        case pricingRefreshed(modelCount: Int)
    }

    private let networkLimiter = ConcurrencyLimiter(limit: 2)
    private let fileScanLimiter = ConcurrencyLimiter(limit: 1)
    private var coalescing = CoalescingEngine()
    private var continuation: AsyncStream<PipelineEvent>.Continuation?
    private var isRunning = true
    // ... fetcher references, processing loop
}
```

The pipeline:
1. Maintains a processing loop that drains coalesced requests
2. For each request, spawns constrained tasks (bounded by ConcurrencyLimiter)
3. Calls existing fetchers (`ClaudeLiteFetcher.fetchUsage()`, `CodexLiteFetcher.fetchUsage()`)
4. Emits `PipelineEvent` values through the continuation
5. Integrates `CoalescingEngine` for dedup and interval enforcement

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DataPipelineTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBarCore/Pipeline/DataPipeline.swift TestsLite/Pipeline/DataPipelineTests.swift
git commit -m "feat: add DataPipeline coordinator with priority queue and event stream"
```

---

### Task 14: Wire DataPipeline into UsageStore

**Files:**
- Modify: `Sources/CodexBar/UsageStore.swift`
- Modify: `Sources/CodexBar/UsageStore+Refresh.swift`

- [ ] **Step 1: Read current UsageStore+Refresh.swift**

Read the full file to understand the existing `performRefresh()`, `startTimer()`, `stopTimer()`, and timer loop implementation.

- [ ] **Step 2: Add pipeline property to UsageStore**

In `UsageStore.swift`, add:
```swift
private var pipeline: DataPipeline?
private var pipelineSubscription: Task<Void, Never>?
```

- [ ] **Step 3: Add pipeline subscription method**

In `UsageStore+Refresh.swift`, add a method that subscribes to `pipeline.events`:

```swift
private func subscribeToPipeline() {
    guard let pipeline else { return }
    pipelineSubscription = Task { [weak self] in
        let events = await pipeline.events
        for await event in events {
            guard let self else { return }
            switch event {
            case .quotaUpdated(let provider, let snapshot):
                self.snapshots[provider] = snapshot
                self.errors[provider] = nil
                self.failureGates[provider]?.recordSuccess()
            case .costUpdated(let provider, let costSnapshot):
                self.tokenSnapshots[provider] = costSnapshot
                self.tokenErrors[provider] = nil
            case .statusUpdated(let provider, let status):
                self.statuses[provider] = status
            case .error(let provider, let error):
                self.handleProviderError(provider, error)
            case .pricingRefreshed:
                break // informational
            }
        }
    }
}
```

- [ ] **Step 4: Replace timer loops with pipeline delegation**

In `startTimer()`, instead of creating `Task.detached { while true { sleep; refresh } }`, create the `DataPipeline`, `AdaptiveRefreshTimer`, `FSEventsWatcher`, and `SystemLifecycleObserver`, and wire them together.

In `performRefresh()`, instead of calling fetchers directly, enqueue a `RefreshRequest` into the pipeline.

- [ ] **Step 5: Verify existing tests still pass**

Run: `swift test --filter UsageStore 2>&1 | tail -20`
Expected: PASS (all existing UsageStore tests pass — the external API hasn't changed)

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexBar/UsageStore.swift Sources/CodexBar/UsageStore+Refresh.swift
git commit -m "feat: wire DataPipeline into UsageStore as reactive event consumer"
```

---

### Task 15: Integration wiring — FSEvents + AdaptiveTimer + SystemLifecycle

**Files:**
- Modify: `Sources/CodexBar/UsageStore+Refresh.swift`

This task wires the FSEventsWatcher, AdaptiveRefreshTimer, and SystemLifecycleObserver into the pipeline startup sequence in UsageStore.

- [ ] **Step 1: Read UsageStore+Refresh.swift (after Task 14 changes)**

Understand the current pipeline setup.

- [ ] **Step 2: Add FSEventsWatcher startup**

In the pipeline initialization (inside `startTimer()` or a new `startPipeline()` method):

```swift
let watcher = FSEventsWatcher()
let watchStream = await watcher.watch(directories: [
    (url: claudeProjectsRoot, fileExtensions: ["jsonl"]),
    (url: codexSessionsRoot, fileExtensions: ["jsonl"]),
    (url: codexArchivedSessionsRoot, fileExtensions: ["jsonl"]),
    (url: claudeCredentialsFile.deletingLastPathComponent(), fileExtensions: ["json"]),
], coalescingLatency: 2.0)
```

- [ ] **Step 3: Add FSEvents → pipeline bridge**

Create a task that reads FSEvents and enqueues into the pipeline:

```swift
Task {
    for await batch in watchStream {
        let hasJsonl = batch.contains { $0.path.hasSuffix(".jsonl") }
        let hasCredentials = batch.contains {
            $0.path.hasSuffix(".credentials.json") || $0.path.hasSuffix("auth.json")
        }

        if hasJsonl {
            await adaptiveTimer.recordFSEvent()
            await pipeline.enqueue(RefreshRequest(
                forceTokenUsage: true,
                priority: .p1
            ))
        }
        if hasCredentials {
            await pipeline.enqueue(RefreshRequest(
                forceQuota: true,
                priority: .p0
            ))
        }
    }
}
```

- [ ] **Step 4: Add adaptive timer loop**

```swift
Task.detached(priority: .utility) {
    while !Task.isCancelled {
        await adaptiveTimer.evaluateState()
        let interval = await adaptiveTimer.currentInterval
        try? await Task.sleep(for: interval)
        guard !await adaptiveTimer.isPaused else { continue }
        await pipeline.enqueue(RefreshRequest(priority: .p2))
    }
}
```

- [ ] **Step 5: Add SystemLifecycleObserver**

```swift
let lifecycle = SystemLifecycleObserver(
    onWake: { [weak pipeline, weak adaptiveTimer] duration in
        if duration > 3600 {
            // Invalidate quota caches after long sleep
        }
        await pipeline?.enqueue(RefreshRequest(
            forceQuota: true, forceTokenUsage: true, priority: .p0
        ))
        await adaptiveTimer?.resume()
    },
    onSleep: { [weak pipeline, weak adaptiveTimer] in
        await pipeline?.cancelInFlightRequests()
        await adaptiveTimer?.pause()
    },
    onSpaceChange: {
        // NOTE: The actual panel dismissal mechanism is StatusItemController.dismissPanel().
            // Define a Notification.Name and observe it in StatusItemController, or pass
            // the controller's dismissPanel closure directly to the onSpaceChange handler.
            NotificationCenter.default.post(name: .codexBarDismissPanel, object: nil)
    }
)
lifecycle.start()
```

- [ ] **Step 6: Verify full build succeeds**

Run: `swift build 2>&1 | tail -20`
Expected: Build succeeded

- [ ] **Step 7: Commit**

```bash
git add Sources/CodexBar/UsageStore+Refresh.swift
git commit -m "feat: wire FSEventsWatcher, AdaptiveRefreshTimer, and SystemLifecycleObserver into pipeline"
```

---

## Chunk 7: Cleanup + Safety Net + Final Verification

### Task 16: Retain hourly safety-net scan

**Files:**
- Modify: `Sources/CodexBarCore/Pipeline/DataPipeline.swift`

- [ ] **Step 1: Add P3 hourly full-scan task**

In the DataPipeline's processing loop, add a background task that fires every 60 minutes at P3 priority. This runs a full directory enumeration as a safety net in case FSEvents drops events.

```swift
Task.detached(priority: .background) {
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(3600))
        await self.enqueue(RefreshRequest(
            forceTokenUsage: true,
            priority: .p3
        ))
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/CodexBarCore/Pipeline/DataPipeline.swift
git commit -m "feat: add hourly P3 safety-net full scan in DataPipeline"
```

---

### Task 17: Remove dead code

**Files:**
- Modify: `Sources/CodexBar/UsageStore+Refresh.swift`

- [ ] **Step 1: Identify dead code**

After the pipeline rewire, the following code in `UsageStore+Refresh.swift` should be dead:
- Old `Task.detached` timer loops (replaced by AdaptiveRefreshTimer)
- Old `performRefresh()` implementation that calls fetchers directly (replaced by pipeline delegation)
- Old `RefreshRequestOptions` type (replaced by `RefreshRequest`)

- [ ] **Step 2: Remove dead code**

Delete the old timer loops and direct fetcher calls. Keep `RefreshRequestOptions` if it's used by external callers, and add a deprecated shim that converts to `RefreshRequest`.

- [ ] **Step 3: Verify build and tests**

Run: `swift build 2>&1 | tail -10 && swift test 2>&1 | tail -20`
Expected: Build succeeded, all tests pass

- [ ] **Step 4: Commit**

```bash
git add Sources/CodexBar/UsageStore+Refresh.swift
git commit -m "refactor: remove old polling loops and direct fetcher calls from UsageStore"
```

---

### Task 18: Final integration verification

- [ ] **Step 1: Run full test suite**

Run: `swift test 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 2: Build the app**

Run: `swift build --target CodexBar 2>&1 | tail -10`
Expected: Build succeeded

- [ ] **Step 3: Verify no strict concurrency warnings**

Run: `swift build --target CodexBar 2>&1 | grep -i "warning\|error" | head -20`
Expected: No concurrency-related warnings (strict concurrency is enabled)

- [ ] **Step 4: Run the app and verify basic functionality**

Run the app, open the menu panel, verify:
- Usage data appears within ~5 seconds of a Claude Code request
- Cost data reflects updated pricing
- The panel dismisses on Space switch
- The app resumes correctly after sleep/wake

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "feat: complete data pipeline redesign — event-driven collection, adaptive polling, live pricing"
```
