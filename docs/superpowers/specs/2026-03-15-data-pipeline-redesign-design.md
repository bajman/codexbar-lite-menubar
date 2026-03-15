# CodexBar Lite — Data Collection & Streaming Pipeline Redesign

**Date:** 2026-03-15
**Status:** Draft
**Scope:** Core data pipeline architecture — collection, caching, deduplication, pricing, and refresh orchestration for Claude and Codex token usage tracking.

---

## 1. Problem Statement

CodexBar Lite's data pipeline is entirely poll-based with no event-driven mechanisms. This causes:

- **Stale data:** Up to 5 minutes for quota, 1 hour for cost data, and indefinite staleness after system sleep.
- **Wasted resources:** API quota probes fire every 5 minutes regardless of user activity; full directory tree enumeration runs hourly.
- **Incorrect data:** Token counts are inflated by deduplication gaps in streaming JSONL entries; hardcoded pricing goes stale; tiered pricing is applied per-category instead of combined; Vertex AI and new model aliases return nil costs.
- **Poor resilience:** No sleep/wake handling, no App Nap prevention, no priority ordering for refresh requests, and file rotation silently corrupts incremental parsing.

### Competitive Context

| Project | Stars | Data Approach | Key Advantage Over CodexBar |
|---|---|---|---|
| ccusage | 11,600 | Local JSONL + LiteLLM pricing | Live pricing, multi-tool monorepo |
| Claude-Usage-Tracker | 1,600 | API polling + multi-profile | Sleep/wake handling, 6-tier pace system |
| tokscale | 1,100 | Rust SIMD parsing + LiteLLM | 16+ platforms, SIMD performance, fuzzy model resolution |
| ClaudeUsageTracker | 104 | LiteLLM API + local fallback | 10-second conversation-turn deduplication |
| cccost | 21 | HTTP fetch interception | Captures requests invisible to JSONL logs |

---

## 2. Design Goals

1. **Sub-5-second data freshness** after any Claude Code or Codex CLI activity.
2. **Zero wasted API calls** during idle periods.
3. **Correct cost calculation** for all model variants, pricing tiers, and log formats.
4. **Resilience** across sleep/wake cycles, file rotation, network failures, and credential changes.
5. **Priority-based refresh** so user-initiated requests are never blocked by background work.
6. **Backward compatibility** — no changes to the UI layer's contract with `UsageStore`.

### Non-Goals

- Supporting additional AI providers beyond Claude and Codex (future work).
- Replacing the OAuth quota probe with a different authentication mechanism.
- Changing the menu bar UI or panel layout.
- HTTP fetch interception (cccost's approach) — too fragile and requires wrapping the CLI process.

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        DataPipeline (actor)                     │
│                                                                 │
│  ┌───────────────┐   ┌──────────────┐   ┌───────────────────┐  │
│  │ Priority Queue │   │  Concurrency │   │    Coalescing     │  │
│  │               │   │   Governor   │   │     Engine        │  │
│  │ P0: user/wake │   │              │   │                   │  │
│  │ P1: fs-event  │   │ 2 network    │   │ Debounce FSEvents │  │
│  │ P2: timer     │   │ 1 file scan  │   │ Dedup providers   │  │
│  │ P3: background│   │              │   │ Merge requests    │  │
│  └───────┬───────┘   └──────┬───────┘   └─────────┬─────────┘  │
│          │                  │                     │             │
│          └──────────────────┼─────────────────────┘             │
│                             │                                   │
│                    ┌────────▼────────┐                          │
│                    │  AsyncStream    │                          │
│                    │ <PipelineEvent> │                          │
│                    └────────┬────────┘                          │
└─────────────────────────────┼───────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
              ┌─────────────────▼─────────────────┐
              │            UsageStore               │
              │  (single @MainActor consumer —      │
              │   quota snapshots, token costs,     │
              │   provider health, all in one)      │
              └─────────────────────────────────────┘
```

### Data Sources (Inputs)

```
┌─────────────────────────────────────────────────────────┐
│                    FSEventsWatcher                       │
│                                                         │
│  Stream A: ~/.claude/projects/     (recursive, *.jsonl) │
│  Stream B: ~/.codex/sessions/      (recursive, *.jsonl) │
│  Stream C: ~/.claude/.credentials.json  (single file)   │
│  Stream D: ~/.codex/auth.json           (single file)   │
│                                                         │
│  Coalescing latency: 2 seconds                          │
│  Persists: lastEventId (survives app restart)           │
│  Emits: FileChangeEvent { path, flags, eventId }        │
└──────────────────────┬──────────────────────────────────┘
                       │
          ┌────────────┼──────────────┐
          │            │              │
   ┌──────▼──────┐ ┌──▼──────────┐ ┌─▼───────────────┐
   │ Quota Probe │ │ Cost Scanner│ │ Credential      │
   │ Trigger     │ │ (incremental│ │ Invalidation    │
   │ (debounced) │ │  w/ finger- │ │ (immediate)     │
   │             │ │  printing)  │ │                 │
   └─────────────┘ └─────────────┘ └─────────────────┘
```

### Refresh Triggers

```
┌──────────────────────────────────────────────────────────────┐
│                    AdaptiveRefreshTimer                       │
│                                                              │
│  State Machine:                                              │
│  ┌──────────┐  FSEvent  ┌──────────┐  15min idle ┌────────┐ │
│  │  ACTIVE  │◄──────────│   IDLE   │◄────────────│  DEEP  │ │
│  │  2min    │──────────►│  15min   │────────────►│ IDLE   │ │
│  │  poll    │  no event │  poll    │  1hr idle   │ 30min  │ │
│  │          │  for 15m  │          │             │ poll   │ │
│  └──────────┘           └──────────┘             └────────┘ │
│                                                              │
│  Additional triggers:                                        │
│  - User click / "Refresh Now" → P0 immediate                │
│  - System wake → P0 with 3-5s delay                         │
│  - Credential file change → P0 immediate                    │
│  - FSEvents JSONL write → P1 with 2-3s debounce             │
└──────────────────────────────────────────────────────────────┘
```

---

## 4. Component Designs

### 4.1 FSEventsWatcher

**Purpose:** Replace polling-based file discovery with event-driven file change detection.

**Responsibilities:**
- Maintain one `FSEventStream` per monitored root directory.
- Filter events to relevant file types (`.jsonl`, `.json`).
- Coalesce rapid events into batched notifications (2-second window).
- Persist the last `FSEventStreamEventId` to UserDefaults so events during app downtime are replayed on relaunch.
- Emit `FileChangeEvent` values through an `AsyncStream`.

**Interface:**

```swift
actor FSEventsWatcher {
    struct FileChangeEvent: Sendable {
        let path: String
        let flags: FSEventStreamEventFlags
        let eventId: FSEventStreamEventId
    }

    /// Watch multiple directory trees simultaneously. Returns a single merged stream.
    /// Each directory gets its own FSEventStream internally; events are merged into
    /// one AsyncStream for the consumer. The stream terminates (yields nil) when
    /// stopAll() is called or the actor is deallocated.
    func watch(
        directories: [(url: URL, fileExtensions: Set<String>)],
        coalescingLatency: TimeInterval = 2.0
    ) -> AsyncStream<[FileChangeEvent]>

    /// Stops all FSEventStreams and terminates the AsyncStream (yields nil).
    /// Safe to call multiple times. After stopAll(), calling watch() again
    /// creates a new stream.
    func stopAll()
}
```

**Stream lifecycle contract:**
- The `AsyncStream` returned by `watch()` yields batched events until `stopAll()` is called.
- On `stopAll()`, the stream's continuation calls `finish()`, causing the consumer's `for await` loop to exit cleanly.
- If the actor is deallocated, `deinit` calls `stopAll()` to ensure cleanup.
- Calling `watch()` after `stopAll()` creates a fresh set of streams and returns a new `AsyncStream`.
- Each call to `watch()` invalidates any previously returned stream (previous stream finishes).

**Key decisions:**
- Use `kFSEventStreamCreateFlagFileEvents` for file-level granularity (not just directory-level).
- Use `kFSEventStreamCreateFlagUseCFTypes` for CF-based API.
- Use `kFSEventStreamCreateFlagNoDefer` to get the first event immediately rather than waiting for the coalescing window.
- Schedule the stream on a dedicated `DispatchQueue` (not main) to avoid blocking UI.
- On `kFSEventStreamEventFlagMustScanSubDirs` (kernel dropped events), emit a synthetic "full rescan needed" event.

**Fallback:** The existing 1-hour full directory enumeration scan is retained as a safety net. It runs on the `P3` (background) priority tier. If FSEvents is unavailable (e.g., network volumes), the system degrades to polling-only mode.

**Error handling:**
- `FSEventStreamCreate` returns `nil` if the directory doesn't exist → watch the parent directory instead and detect creation.
- Dead stream detection: The watcher tracks whether the FSEventStream callback has been invoked at all (for any event, including irrelevant file types) within the last 60 minutes. If zero callbacks fire for 60+ minutes, the stream may be dead — invalidate it and recreate. This is distinct from "no JSONL writes" (which is normal during idle periods). The check is: "has the OS delivered any FSEvents callback at all?" not "have relevant files changed?"

---

### 4.2 ContentFingerprintedIncrementalParser

**Purpose:** Make incremental JSONL parsing resilient to file rotation, truncation, and replacement.

**Current problem:** The scanner resumes from a byte offset without verifying the file is the same one that was previously parsed. Log rotation (file replaced with new content at same path) produces garbage.

**Cache entry structure:**

```swift
struct CachedFileEntry: Codable {
    let path: String
    let size: Int64
    let lastModified: Date
    let parsedOffset: Int64
    let headerFingerprint: Data    // SHA256 of first 4096 bytes
    let inodeIdentifier: UInt64    // stat().st_ino
    let lastEventId: FSEventStreamEventId?
}
```

**Parse decision logic:**

```
Given: cached entry C, current file F

1. If C.inodeIdentifier != F.inode → FULL REPARSE (file replaced)
2. If C.headerFingerprint != SHA256(F[0..<4096]) → FULL REPARSE (content changed at start)
3. If F.size < C.parsedOffset → FULL REPARSE (file truncated)
4. If F.size == C.size && F.lastModified == C.lastModified → SKIP (unchanged)
5. If F.size > C.parsedOffset → INCREMENTAL from C.parsedOffset
```

**Integration with FSEventsWatcher:**
- FSEvents tells us *which* files changed → only process those files.
- On "full rescan needed" events → enumerate all files but still use fingerprint checks to skip unchanged ones.
- New files (no cache entry) → full parse from offset 0.

---

### 4.3 Provider-Aware Deduplication Pipeline

**Purpose:** Eliminate inflated token counts from JSONL log entries where the same usage can appear multiple times.

**Current problem:** Deduplication only works when both `messageId` and `requestId` are present. Entries with either ID missing are not deduplicated at all.

**Important format distinction:** Claude and Codex JSONL logs have fundamentally different formats:
- **Claude:** Each `type: "assistant"` entry contains the *final* usage for that message. Multiple entries for the same message arise from streaming log writes (each write has the same cumulative totals). Entries have `message.id` and `requestId` but no `sessionId`.
- **Codex:** Entries contain `total_token_usage` which is a *running cumulative total* across the entire session. The app computes deltas between consecutive entries. Entries have a `sessionId` from `session_meta`.

The deduplication strategy is therefore provider-specific:

#### Claude Deduplication (two layers)

**Layer 1 — Key-based (existing, corrected):**
```
If message.id AND requestId both present:
    key = "\(message.id):\(requestId)"
    If key in seenKeys → skip
    Else → insert key, process entry
```

**Layer 2 — Temporal grouping (new, for entries with missing IDs):**
```
If message.id present but requestId nil (or vice versa):
    groupKey = "\(filePath):\(model):\(roundedTimestamp5s)"
    Accumulate into temporalGroups[groupKey]
    After file fully parsed, emit MAX token counts per group
```

Rationale: When both IDs aren't available, group by file path (which acts as a project/session proxy since Claude logs are per-project), model, and a 5-second time window. Since Claude entries contain final cumulative usage for a message, taking the maximum from a temporal group gives the correct totals even if the same message was logged multiple times.

Note: `filePath` is used instead of `sessionId` because Claude JSONL entries do not have a `sessionId` field. The file path serves as an equivalent grouping key since Claude logs are partitioned by project directory.

#### Codex Deduplication (delta-aware)

Codex uses cumulative `total_token_usage` counters. The existing delta computation (`max(0, current - previous)`) is retained with one fix:

**Counter reset detection (new):**
```
Given: previousTotals P, currentTotals C

If C.inputTokens < P.inputTokens AND C.outputTokens < P.outputTokens:
    // Session restarted — counters reset to zero and began a new session.
    // Treat C as absolute values (not deltas) for this entry.
    delta = C  (use current totals directly, not max(0, C - P))
Else:
    delta = max(0, C - P)  (existing behavior)

Update previousTotals = C
```

This fixes Bug 5 (Codex counter reset token loss). The key insight is that a *simultaneous* drop in both input and output counters signals a session restart, whereas a drop in just one counter would indicate a data anomaly (clamped to zero as before).

**Deduplication scope:** Per-file for Claude. Per-session for Codex (since Codex entries reference `sessionId` and deltas span entries). The `seenKeys` set is built per file parse and merged into the global state.

---

### 4.4 LiteLLM-Based Pricing Resolver

**Purpose:** Replace hardcoded pricing with live data that auto-updates when models change.

**Current problem:** Hardcoded `CostUsagePricing.swift` goes stale. Missing models (`claude-sonnet-4-1`, Vertex AI `@` format, `[1m]` bracket notation) return `nil` cost. Tiered pricing threshold is applied per-category instead of combined.

**Five-layer resolution:**

```
PricingResolver
│
├── Layer 1: In-memory cache (session lifetime, ~2MB parsed)
│
├── Layer 2: Disk cache at ~/.codexbar/cache/pricing-litellm.json
│            TTL: 24 hours
│            Written atomically (temp file + rename)
│
├── Layer 3: Network fetch
│            URL: https://raw.githubusercontent.com/BerriAI/litellm/main/
│                 model_prices_and_context_window.json
│            HTTP ETag/If-None-Match for conditional fetching
│            3 retries, exponential backoff: 200ms → 400ms → 800ms
│            30-second request timeout
│
├── Layer 4: Stale disk cache (any age, if network fails)
│
└── Layer 5: Embedded pricing snapshot (compiled into binary)
             Updated at each app release via build script
```

**Model name resolution chain** (adapted from tokscale):

This replaces the existing `normalizeClaudeModel` (CostUsagePricing.swift lines 179-206) and `normalizeCodexModel` (lines 167-177) functions with a unified resolver. The existing functions are retained as step 3's implementation, extended with the additional resolution steps.

```
1. Exact match in LiteLLM pricing table
2. Alias map (hardcoded for known short forms):
   - "claude-sonnet-4-1" → look up with current date suffix
   - "claude-opus-4-6" → look up with current date suffix
   (Note: actual date suffixes must be verified against Anthropic's
    model release documentation at implementation time. The alias map
    is a static dictionary, not generated.)
3. Strip date suffix via existing regex: #"-\d{8}$"# (e.g., "-20250514")
4. Convert Vertex '@' to '-': "claude-opus-4-5@20251101" → "claude-opus-4-5-20251101"
   (then retry from step 1 with the converted name)
5. Strip bracket notation: "claude-opus-4-6[1m]" → "claude-opus-4-6"
   (then retry from step 1 with the stripped name)
6. Provider prefix matching: try prepending "anthropic/", "openai/" prefixes
   (LiteLLM often uses provider-prefixed keys)
7. Fuzzy word-boundary matching (last resort): split model name on "-" and
   find the pricing entry with the most matching word segments
```

**Tiered pricing fix:**

The current bug: `CostUsagePricing.claudeCostUSD` (lines 228-254) applies the `tiered()` function independently to each token category (input, cacheRead, cacheCreate, output). This is wrong in two ways:
1. The 200K threshold should apply to the *combined* input context (input + cacheRead + cacheCreate), not each independently.
2. Output tokens should *never* use tiered pricing — Anthropic's pricing tiers are based on input context length, not output length.

**Behavioral change note:** This fix will change cost calculations for users whose combined input context exceeds 200K tokens but whose individual token categories do not. Costs will increase slightly for these users (correct behavior). Output costs will decrease slightly for hypothetical cases where output exceeded 200K tokens (which is practically impossible with current context windows but was being overcharged). A one-time cache invalidation on upgrade is required (see Section 8, Phase 3).

**Complete allocation algorithm:**

The 200K threshold is a shared budget consumed by input token categories in this order: (1) regular input tokens, (2) cache creation tokens, (3) cache read tokens. Each category consumes from the remaining budget.

```swift
func cost(for usage: TokenUsage, model: String) -> CostResult {
    guard let pricing = resolve(model: model) else { return .unknown }
    guard let threshold = pricing.tieredThreshold else {
        // No tiered pricing for this model — flat rate
        return .flat(
            input: usage.inputTokens * pricing.inputCostPerToken,
            cacheRead: usage.cacheReadInputTokens * pricing.cacheReadCostPerToken,
            cacheCreate: usage.cacheCreationInputTokens * pricing.cacheCreateCostPerToken,
            output: usage.outputTokens * pricing.outputCostPerToken
        )
    }

    // Shared budget for the tiered threshold across all input categories.
    // Categories consume the budget in order: input → cacheCreate → cacheRead.
    var remainingBudget = threshold  // e.g., 200_000

    // 1. Regular input tokens
    let inputBase = min(usage.inputTokens, remainingBudget)
    let inputOverage = usage.inputTokens - inputBase
    remainingBudget -= inputBase

    // 2. Cache creation tokens (consume next from remaining budget)
    let cacheCreateBase = min(usage.cacheCreationInputTokens, remainingBudget)
    let cacheCreateOverage = usage.cacheCreationInputTokens - cacheCreateBase
    remainingBudget -= cacheCreateBase

    // 3. Cache read tokens (consume last from remaining budget)
    let cacheReadBase = min(usage.cacheReadInputTokens, remainingBudget)
    let cacheReadOverage = usage.cacheReadInputTokens - cacheReadBase
    // remainingBudget not needed after this

    // Compute costs: base tokens at base rate, overage at overage rate
    let inputCost = Double(inputBase) * pricing.inputCostPerToken
                  + Double(inputOverage) * pricing.inputCostPerTokenAboveThreshold
    let cacheCreateCost = Double(cacheCreateBase) * pricing.cacheCreateCostPerToken
                        + Double(cacheCreateOverage) * pricing.cacheCreateCostPerTokenAboveThreshold
    let cacheReadCost = Double(cacheReadBase) * pricing.cacheReadCostPerToken
                      + Double(cacheReadOverage) * pricing.cacheReadCostPerTokenAboveThreshold

    // 4. Output tokens: ALWAYS flat rate, never tiered.
    // Anthropic's pricing documentation specifies tiered pricing for input
    // context only. Output pricing is independent of input context length.
    // Citation: https://docs.anthropic.com/en/docs/about-claude/models
    let outputCost = Double(usage.outputTokens) * pricing.outputCostPerToken

    return .tiered(input: inputCost, cacheRead: cacheReadCost,
                   cacheCreate: cacheCreateCost, output: outputCost)
}
```

**Refresh schedule:** Pricing is fetched once on app launch, then every 24 hours. A forced refresh occurs when a model name lookup fails (unknown model → maybe pricing data is stale).

---

### 4.5 System Lifecycle Observer

**Purpose:** Handle sleep/wake, App Nap, and screen lock transitions.

**Current problem:** No sleep/wake handling. Timers drift. Stale data displayed after wake. App Nap can throttle timers silently.

**Implementation:**

```swift
/// @MainActor because it interacts with NSWorkspace notifications (which deliver
/// on main) and needs to coordinate with the DataPipeline actor and
/// AdaptiveRefreshTimer actor via async calls.
@MainActor
final class SystemLifecycleObserver {
    private var activityToken: NSObjectProtocol?
    private var sleepTimestamp: Date?
    private let pipeline: DataPipeline
    private let adaptiveTimer: AdaptiveRefreshTimer
    private let quotaCache: ClaudeCodeQuotaCache

    func start() {
        // Prevent App Nap from throttling timers
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "CodexBar usage monitoring"
        )

        let ws = NSWorkspace.shared.notificationCenter

        // Sleep: record timestamp, cancel in-flight requests.
        // Notification delivers on main queue → closure is @MainActor-isolated.
        ws.addObserver(forName: NSWorkspace.willSleepNotification, ...) { [weak self] _ in
            guard let self else { return }
            self.sleepTimestamp = Date()
            // pipeline and adaptiveTimer are actors — must use Task for async calls
            Task {
                await self.pipeline.cancelInFlightRequests()
                await self.adaptiveTimer.pause()
            }
        }

        // Wake: delayed refresh
        ws.addObserver(forName: NSWorkspace.didWakeNotification, ...) { [weak self] _ in
            guard let self else { return }
            let sleepDuration = Date().timeIntervalSince(self.sleepTimestamp ?? Date())

            Task {
                // Wait for network interfaces to reconnect
                try? await Task.sleep(for: .seconds(sleepDuration > 3600 ? 5 : 3))

                // If slept > 1 hour, invalidate all cached quota data
                if sleepDuration > 3600 {
                    await self.quotaCache.invalidateAll()
                }

                await self.pipeline.enqueue(RefreshRequest(
                    forceQuota: true,
                    forceTokenUsage: true,
                    priority: .p0
                ))
                await self.adaptiveTimer.resume()
            }
        }

        // Space switch: dismiss panel (UI concern, forwarded to StatusItemController)
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, ...) { _ in
            NotificationCenter.default.post(name: .dismissMenuPanel, object: nil)
        }
    }
}
```

**App Nap details:**
- The `beginActivity` token must be held for the entire app lifetime.
- `userInitiatedAllowingIdleSystemSleep` prevents timer throttling but still allows the system to sleep when the user closes the lid.
- This is the same approach used by other always-on menu bar apps (e.g., iStat Menus, Bartender).

---

### 4.6 Adaptive Refresh Timer

**Purpose:** Replace the fixed-interval polling timer with an activity-aware adaptive timer that polls aggressively during active use and backs off during idle periods.

**State machine:**

```swift
actor AdaptiveRefreshTimer {
    enum State {
        case active    // FSEvents activity in last 15 minutes → poll every 2 min
        case idle      // No FSEvents for 15-60 minutes → poll every 15 min
        case deepIdle  // No FSEvents for 60+ minutes → poll every 30 min
    }

    private var state: State = .idle
    private var lastFSEventTimestamp: Date?

    /// Called by FSEventsWatcher when JSONL files change.
    func recordFSEvent() {
        lastFSEventTimestamp = Date()
        if state != .active {
            state = .active
            // Trigger immediate quota probe (debounced 2-3s)
            pipeline.enqueue(.fsEventTriggered, priority: .p1, debounce: .seconds(3))
        }
    }

    /// Returns the current polling interval.
    var currentInterval: Duration {
        switch state {
        case .active:   return .seconds(120)
        case .idle:     return .seconds(900)
        case .deepIdle: return .seconds(1800)
        }
    }

    /// Called periodically to transition states.
    func evaluateState() {
        guard let last = lastFSEventTimestamp else {
            state = .deepIdle
            return
        }
        let elapsed = Date().timeIntervalSince(last)
        switch elapsed {
        case ..<900:    state = .active
        case ..<3600:   state = .idle
        default:        state = .deepIdle
        }
    }
}
```

**User-configurable override:** The existing `SettingsStore.refreshFrequency` setting is retained. If the user sets a manual interval, it overrides the adaptive timer for the `P2` (timer) tier. FSEvents-triggered refreshes (`P1`) still fire regardless.

---

### 4.7 DataPipeline Coordinator

**Purpose:** Replace the current three independent polling loops with a unified, priority-ordered pipeline that coordinates all data fetching.

**Priority tiers:**

| Priority | Trigger | Latency Target | Examples |
|---|---|---|---|
| P0 | User action, wake-from-sleep, credential change | < 1 second to start | "Refresh Now" click, system wake |
| P1 | FSEvents JSONL write | < 5 seconds | Claude Code completed a request |
| P2 | Adaptive timer | Best-effort | Background polling |
| P3 | Background maintenance | Deferred | Full directory rescan, pricing refresh, status page check |

**Concurrency governor:**

Bounded concurrency is implemented via a custom `ConcurrencyLimiter` actor (not `AsyncSemaphore`, which does not exist in the Swift standard library). This is a simple actor wrapping a counter and a list of continuations:

```swift
/// Custom concurrency limiter. Not a semaphore — uses Swift concurrency
/// primitives (continuations) rather than OS-level synchronization.
actor ConcurrencyLimiter {
    private let limit: Int
    private var active: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

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
        active -= 1
        if let next = waiters.first {
            waiters.removeFirst()
            active += 1
            next.resume()
        }
    }
}

actor DataPipeline {
    private let networkLimiter = ConcurrencyLimiter(limit: 2)
    private let fileScanLimiter = ConcurrencyLimiter(limit: 1)

    // Network requests (quota probes, pricing fetch, status check)
    // can run 2 at a time (one per provider).
    // File scans (cost usage) run 1 at a time.
    // Network preempts file scans: if a P0/P1 network request arrives
    // while a P3 file scan is running, the file scan is suspended
    // (via Task cancellation + restart from last good offset).
}
```

**RefreshRequest type:**

The existing `RefreshRequestOptions` in `UsageStore.swift` (lines 124-132) has `forceTokenUsage` and `forceStatusChecks`. The pipeline extends this:

```swift
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

    enum Priority: Int, Comparable {
        case p0 = 0  // user/wake
        case p1 = 1  // fs-event
        case p2 = 2  // timer
        case p3 = 3  // background

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }
}
```

**Coalescing engine:**

```swift
struct CoalescingEngine {
    /// Multiple FSEvents within 2 seconds → single batched scan
    func debounce(event: FileChangeEvent, window: Duration = .seconds(2))

    /// Multiple refresh requests while one is in-flight → merge flags.
    /// The merged request takes the highest priority (lowest rawValue)
    /// and OR's together all force flags.
    func mergeRefreshRequest(_ request: RefreshRequest) {
        pendingRequest.forceTokenUsage |= request.forceTokenUsage
        pendingRequest.forceStatusChecks |= request.forceStatusChecks
        pendingRequest.forceQuota |= request.forceQuota
        pendingRequest.providers.formUnion(request.providers)
        pendingRequest.priority = min(pendingRequest.priority, request.priority)
    }

    /// Don't probe the same provider twice within minimum interval.
    /// Returns true if the request should be skipped.
    func shouldSkip(provider: UsageProvider, kind: FetchKind) -> Bool {
        // Claude quota: 30s minimum (user-initiated / P0), 60s (background / P1-P3)
        // Codex quota: same intervals
        // Cost scan: 10s minimum (FSEvents-triggered / P1), 300s (timer / P2-P3)
    }
}
```

**Output stream:**

```swift
extension DataPipeline {
    enum PipelineEvent: Sendable {
        case quotaUpdated(UsageProvider, UsageSnapshot)
        case costUpdated(UsageProvider, CostUsageTokenSnapshot)
        case statusUpdated(UsageProvider, ProviderStatus)
        case error(UsageProvider, Error)
        case pricingRefreshed(modelCount: Int)
    }

    /// Subscribe to pipeline events. UsageStore consumes this.
    /// Buffering policy: `.bufferingNewest(20)` — if the @MainActor consumer
    /// is slow to drain, only the 20 most recent events are kept. Older events
    /// are dropped. This prevents unbounded memory growth. Since events are
    /// state snapshots (not deltas), dropping older events is safe — the latest
    /// event for each provider always contains the current state.
    var events: AsyncStream<PipelineEvent> { get }
}
```

**UsageStore integration:**

The current `performRefresh()` method is replaced with a subscription:

```swift
// In UsageStore.init or start():
Task {
    for await event in pipeline.events {
        switch event {
        case .quotaUpdated(let provider, let snapshot):
            self.snapshots[provider] = snapshot
            self.errors[provider] = nil
            self.failureGates[provider]?.recordSuccess()
        case .costUpdated(let provider, let costSnapshot):
            self.tokenSnapshots[provider] = costSnapshot
        case .error(let provider, let error):
            self.handleProviderError(provider, error)
        // ...
        }
    }
}
```

This decouples the UI state store from the data fetching mechanics. The `UsageStore` becomes a pure reactive consumer.

---

## 5. Bug Fixes Included in This Redesign

These bugs from the analysis are directly addressed by the architectural changes above:

| Bug # | Description | Fixed By |
|---|---|---|
| 1 | Tiered pricing per-category instead of combined | 4.4 (PricingResolver tiered pricing fix) |
| 2 | Missing model aliases (sonnet-4-1, opus-4-6[1m]) | 4.4 (model name resolution chain) |
| 4 | Vertex AI `@` format not normalized | 4.4 (step 4 of resolution chain) |
| 5 | Codex counter reset token loss | 4.3 (Codex counter reset detection in delta computation) |
| 7 | Unstable `String(describing:)` for file identity | 4.2 (inode-based identity) |
| 8 | Date-range pruning evicts valid cache | 4.2 (fingerprint-based cache, no range pruning) |
| 9 | Deduplication fails with nil messageId/requestId | 4.3 (provider-aware deduplication: Claude two-layer + Codex delta-aware) |
| 11 | Directory mtime optimization skips modified files | 4.1 (FSEvents replaces mtime checks) |
| 12 | File rotation corrupts incremental parsing | 4.2 (content fingerprinting) |
| 14 | Empty file in skip path leaves stale cache | 4.2 (size=0 triggers cache eviction) |

## 6. Bug Fixes NOT Included (Separate Work)

These bugs require targeted fixes but are not part of the pipeline redesign:

| Bug # | Description | Recommended Fix |
|---|---|---|
| 15 | `resetSeconds` header interpretation (Unix epoch vs seconds-remaining) | Confirmed: values are Unix epoch. Add comment documenting this. |
| 16-18 | Quota fetcher minor issues (token change race, lastAttemptAt timing, formatter allocation) | Small targeted fixes in ClaudeCodeQuotaFetcher. |
| 19 | 5-hour session window assumed from first message | Cannot be fixed without server-side data. Document as known limitation. |
| 20-24 | Minor logic issues (scanSince formatting, tier matching, historical outlier, enterprise subscription, disabled provider iteration) | Targeted fixes in respective files. |
| 25-33 | UsageStore and ClaudeLiteFetcher edge cases | Targeted fixes; some are resolved by the pipeline redesign (e.g., 28 is eliminated by the DataPipeline replacing the current refresh loop). |

---

## 7. UI/UX Fixes (Separate Track)

The analysis identified 30+ UI/UX issues. These are out of scope for this spec but should be tracked separately. The most critical ones that interact with the pipeline redesign:

1. **Panel dismiss/show race** (Bug from UI analysis) — Resolved naturally by the reactive `UsageStore` subscription model, which eliminates the current tight coupling between refresh cycles and UI updates.
2. **No loading indicator on first open** — The `PipelineEvent` stream enables the UI to distinguish between "no data yet" (initial state) and "data fetched, nothing to show" (empty result).
3. **Space switch doesn't dismiss panel** — Addressed by `SystemLifecycleObserver` (Section 4.5).

---

## 8. Migration Strategy

The redesign is backward-compatible at the `UsageStore` API level. The migration is internal:

**Phase 1:** Add FSEventsWatcher and ContentFingerprintedIncrementalParser alongside existing code. Wire FSEvents into cost scanning but keep the existing timer as primary. FSEvents watches `~/.codex/archived_sessions/` in addition to `~/.codex/sessions/` since the existing cost scanner already enumerates archived sessions (see `CostUsageScanner.swift` lines 116-129 where `codexSessionsRoots` includes `archived_sessions`). The overhead is minimal and maintains consistency.

**Phase 2:** Add PricingResolver. Replace hardcoded pricing lookups with resolver calls. Keep hardcoded table as Layer 5 fallback.

**Phase 3:** Add provider-aware deduplication to CostUsageScanner+Claude.swift and CostUsageScanner.swift. This replaces the existing Claude dedup logic and adds counter-reset detection for Codex. **Note:** The improved deduplication will produce different (lower, more accurate) token counts for some users. Trigger a one-time cost usage cache invalidation on first launch after upgrade by incrementing the cache version from `v1` to `v2`. This forces a full reparse of all JSONL files with the corrected deduplication logic. Users will see a brief "Recalculating costs..." state on first launch.

**Phase 4:** Add SystemLifecycleObserver and AdaptiveRefreshTimer. Replace the fixed `Task.sleep` loops in UsageStore.

**Phase 5:** Add DataPipeline coordinator. Rewire UsageStore to consume `AsyncStream<PipelineEvent>` instead of calling fetchers directly. Remove old refresh orchestration code.

**Phase 6:** Remove dead code — old polling loops, old file enumeration in cost scanner (except as P3 safety net), old hardcoded pricing (except as Layer 5 fallback).

### Cache Format Migration

The current `CostUsageFileUsage` struct (in `CostUsageCache.swift`) stores `mtimeUnixMs`, `size`, `parsedBytes`, `lastModel`, `lastTotals`, `sessionId`. The proposed `CachedFileEntry` (Section 4.2) adds `headerFingerprint` and `inodeIdentifier` and renames fields.

**Migration strategy:**
- The cache file uses a `version` field that is checked on load. Current version: `1`.
- Phase 1 increments to version `2`. The new format adds `headerFingerprint: Data` and `inodeIdentifier: UInt64`.
- On load, if `version < 2`: **discard the entire cache** and perform a full reparse. This is safe because:
  - The full reparse happens once, on first launch after upgrade.
  - The reparse is bounded in time by Phase 1's integration with FSEvents (subsequent updates are incremental).
  - No data is lost — the cache is a derived artifact from JSONL source files.
- The version `2` cache is written atomically after the first full reparse completes.
- Phase 3's dedup improvement triggers a second version bump to `3`, which again forces a full reparse. To avoid two consecutive full reparses across phases, **Phases 1 and 3 should be deployed together** (single app update) so only one reparse occurs.

**Pricing cache persistence across app updates:** The pricing disk cache at `~/.codexbar/cache/pricing-litellm.json` uses a version-independent path and is preserved across app updates. The cache includes a `fetchedAt` timestamp; the 24-hour TTL ensures stale pricing is refreshed regardless of app version.

---

## 9. Testing Strategy

### Unit Tests

| Component | Test Focus |
|---|---|
| FSEventsWatcher | Mock FSEventStream callback; verify coalescing, filtering, eventId persistence |
| ContentFingerprintedIncrementalParser | Rotation detection, truncation, fingerprint mismatch, normal incremental append |
| Three-layer deduplication | Streaming chunks with nil IDs, temporal grouping, monotonicity check, edge cases |
| PricingResolver | Model name resolution chain (all 7 steps), tiered pricing calculation, cache fallback hierarchy |
| AdaptiveRefreshTimer | State transitions, interval calculations, FSEvent recording |
| CoalescingEngine | Debouncing, request merging, minimum interval enforcement |

### Integration Tests

| Scenario | Validation |
|---|---|
| File rotation during active scan | Fingerprint detects change, full reparse produces correct totals |
| Sleep → wake → refresh | Data refreshes within 5s of wake, no stale display |
| Rapid Claude Code usage | FSEvents triggers probe within 5s, not on every individual write |
| Network failure during pricing fetch | Falls back through layers gracefully, eventually uses embedded data |
| New model appears in logs | Pricing resolver fetches updated data or uses fuzzy match |

### Performance Benchmarks

| Metric | Target | Current Baseline |
|---|---|---|
| Time from JSONL write to UI update | < 5 seconds | 5-60 minutes |
| API calls per hour, total across all providers (active use) | < 30 (quota probes only; includes both timer polls at 2min intervals = ~30/hr/provider, minus coalescing when FSEvents-triggered probes replace timer polls within the same minimum interval window) | ~12 (fixed, per provider) |
| API calls per hour, total across all providers (idle) | < 4 (2 providers × 2 polls/hr at 30min interval) | ~24 (12 per provider, same regardless of activity) |
| Cost scan CPU time (1000 JSONL files) | < 500ms (incremental) | ~2-5s (full enumeration) |
| Memory overhead of pricing cache | < 3MB | ~0 (hardcoded) |

---

## 10. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| FSEvents drops events (kernel overflow) | Missed JSONL changes → stale cost data | `kFSEventStreamEventFlagMustScanSubDirs` handler triggers full rescan; hourly safety-net scan retained |
| LiteLLM pricing JSON schema changes | Pricing parser breaks | Schema validation with graceful fallback to embedded data; alert user if pricing data is > 7 days old |
| Anthropic changes rate-limit header format | Quota probe returns wrong data | `detectUtilizationScale` heuristic retained (with fixes); monitor for header changes via ccusage/Claude-Usage-Tracker issue trackers |
| FSEventsWatcher increases battery usage | User complaints | Coalescing latency is 2s (not real-time); only monitors 2-4 directories; benchmarks show < 0.1% CPU |
| DataPipeline actor contention | Slow refreshes | Priority queue ensures user-initiated requests bypass background work; concurrency governor prevents resource exhaustion |
| Embedded pricing snapshot is very stale (old app version) | Incorrect costs for new models | Show "pricing data may be outdated" warning if embedded data is > 90 days old and network fetch has failed for > 7 days |

---

## 11. Open Questions

1. **Should the adaptive timer be user-configurable?** The current `refreshFrequency` setting maps to a fixed interval. Options: (a) keep it as an override for the P2 tier, (b) replace it with an "Aggressive / Balanced / Conservative" selector, (c) remove it entirely and let the adaptive timer handle everything.

2. ~~**Should we persist the pricing disk cache across app updates?**~~ **Resolved:** Yes. The pricing cache at `~/.codexbar/cache/pricing-litellm.json` uses a version-independent path and is preserved across app updates (see Section 8, Cache Format Migration).

3. ~~**Should FSEvents watch `~/.codex/archived_sessions/` too?**~~ **Resolved:** Yes. The existing cost scanner already enumerates `archived_sessions` (see `CostUsageScanner.swift` lines 116-129). FSEvents should watch it for consistency. The overhead is minimal.
