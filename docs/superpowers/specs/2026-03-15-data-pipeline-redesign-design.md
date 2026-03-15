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
    ┌─────────▼──────┐ ┌─────▼──────┐ ┌──────▼──────┐
    │  UsageStore     │ │ CostStore  │ │ StatusStore │
    │ (quota snapshots│ │ (token $)  │ │ (provider   │
    │  reset times)   │ │            │ │  health)    │
    └────────────────┘ └────────────┘ └─────────────┘
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

    /// Start watching a directory tree. Returns a stream of change events.
    func watch(
        directory: URL,
        fileExtensions: Set<String>,
        coalescingLatency: TimeInterval = 2.0
    ) -> AsyncStream<[FileChangeEvent]>

    /// Stop watching and clean up.
    func stopAll()
}
```

**Key decisions:**
- Use `kFSEventStreamCreateFlagFileEvents` for file-level granularity (not just directory-level).
- Use `kFSEventStreamCreateFlagUseCFTypes` for CF-based API.
- Use `kFSEventStreamCreateFlagNoDefer` to get the first event immediately rather than waiting for the coalescing window.
- Schedule the stream on a dedicated `DispatchQueue` (not main) to avoid blocking UI.
- On `kFSEventStreamEventFlagMustScanSubDirs` (kernel dropped events), emit a synthetic "full rescan needed" event.

**Fallback:** The existing 1-hour full directory enumeration scan is retained as a safety net. It runs on the `P3` (background) priority tier. If FSEvents is unavailable (e.g., network volumes), the system degrades to polling-only mode.

**Error handling:**
- `FSEventStreamCreate` returns `nil` if the directory doesn't exist → watch the parent directory instead and detect creation.
- If the stream stops delivering events for 30+ minutes without any JSONL writes, trigger a manual rescan (dead stream detection).

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

### 4.3 Three-Layer Deduplication Pipeline

**Purpose:** Eliminate inflated token counts from Claude's streaming JSONL format.

**Current problem:** Deduplication only works when both `messageId` and `requestId` are present. Streaming chunks with missing IDs are counted multiple times.

**Layer 1 — Key-based (existing, corrected):**
```
If messageId AND requestId present:
    key = "\(messageId):\(requestId)"
    If key in seenKeys → skip
    Else → insert key, process entry
```

**Layer 2 — Temporal grouping (new):**
```
If messageId present but requestId nil (or vice versa):
    groupKey = "\(sessionId):\(model):\(roundedTimestamp5s)"
    Accumulate into temporalGroups[groupKey]
    After file fully parsed, emit MAX token counts per group
```

Rationale: Claude streaming chunks emit cumulative token counts. The last chunk in a temporal group has the correct final totals. Taking the maximum handles out-of-order delivery.

**Layer 3 — Monotonicity check (new):**
```
Within each (sessionId, messageId) group:
    If new entry's inputTokens < previously seen inputTokens for same messageId → skip
    (Streaming chunks are cumulative; lower counts are earlier partial chunks)
```

**Deduplication scope:** Per-file. The `seenKeys` set is built per file parse and merged into the global state. This matches the current architecture where files are parsed independently.

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

```
1. Exact match in pricing table
2. Alias map: {"claude-sonnet-4-1" → "claude-sonnet-4-1-20250514", ...}
3. Strip date suffix: "claude-sonnet-4-1-20250514" → "claude-sonnet-4-1"
4. Convert Vertex '@' to '-': "claude-opus-4-5@20251101" → "claude-opus-4-5-20251101"
5. Strip bracket notation: "claude-opus-4-6[1m]" → "claude-opus-4-6"
6. Provider prefix matching: try "anthropic/", "openai/" prefixes
7. Fuzzy word-boundary matching (last resort)
```

**Tiered pricing fix:**

The 200K token threshold for Sonnet 4.5 must be applied to the *combined* input context:

```swift
func cost(for usage: TokenUsage, model: String) -> CostResult {
    let totalInputContext = usage.inputTokens
        + usage.cacheReadInputTokens
        + usage.cacheCreationInputTokens

    let pricing = resolve(model: model)

    // Input tokens: split at threshold
    let baseInputTokens = min(usage.inputTokens, max(0, pricing.threshold - otherInputTokens))
    let overageInputTokens = usage.inputTokens - baseInputTokens

    // Cache tokens: remainder of threshold after input tokens consumed
    // ... (same split logic)

    // Output tokens: NEVER use tiered pricing (output is independent of input context length)
    let outputCost = Double(usage.outputTokens) * pricing.outputCostPerToken
}
```

**Refresh schedule:** Pricing is fetched once on app launch, then every 24 hours. A forced refresh occurs when a model name lookup fails (unknown model → maybe pricing data is stale).

---

### 4.5 System Lifecycle Observer

**Purpose:** Handle sleep/wake, App Nap, and screen lock transitions.

**Current problem:** No sleep/wake handling. Timers drift. Stale data displayed after wake. App Nap can throttle timers silently.

**Implementation:**

```swift
final class SystemLifecycleObserver {
    private var activityToken: NSObjectProtocol?
    private var sleepTimestamp: Date?

    func start() {
        // Prevent App Nap from throttling timers
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "CodexBar usage monitoring"
        )

        let ws = NSWorkspace.shared.notificationCenter

        // Sleep: record timestamp, cancel in-flight requests
        ws.addObserver(forName: NSWorkspace.willSleepNotification, ...) {
            self.sleepTimestamp = Date()
            self.pipeline.cancelInFlightRequests()
            self.adaptiveTimer.pause()
        }

        // Wake: delayed refresh
        ws.addObserver(forName: NSWorkspace.didWakeNotification, ...) {
            let sleepDuration = Date().timeIntervalSince(self.sleepTimestamp ?? Date())

            // Wait for network interfaces to reconnect
            Task {
                try await Task.sleep(for: .seconds(sleepDuration > 3600 ? 5 : 3))
                await self.pipeline.enqueue(.wake, priority: .p0)
            }

            // If slept > 1 hour, invalidate all cached quota data
            if sleepDuration > 3600 {
                self.quotaCache.invalidateAll()
            }

            self.adaptiveTimer.resume()
        }

        // Space switch: dismiss panel (UI concern, forwarded to StatusItemController)
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, ...) {
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

```swift
actor DataPipeline {
    private let networkSemaphore = AsyncSemaphore(limit: 2)
    private let fileScanSemaphore = AsyncSemaphore(limit: 1)

    // Network requests (quota probes, pricing fetch, status check)
    // can run 2 at a time (one per provider).
    // File scans (cost usage) run 1 at a time.
    // Network preempts file scans: if a P0/P1 network request arrives
    // while a P3 file scan is running, the file scan is suspended
    // (via Task cancellation + restart from last good offset).
}
```

**Coalescing engine:**

```swift
struct CoalescingEngine {
    /// Multiple FSEvents within 2 seconds → single batched scan
    func debounce(event: FileChangeEvent, window: Duration = .seconds(2))

    /// Multiple refresh requests while one is in-flight → merge flags
    func mergeRefreshRequest(_ request: RefreshRequest) {
        // OR together: forceTokenUsage, forceStatusChecks, forceQuota
        pendingRequest.forceTokenUsage |= request.forceTokenUsage
        pendingRequest.forceStatusChecks |= request.forceStatusChecks
    }

    /// Don't probe the same provider twice within minimum interval
    func shouldSkip(provider: UsageProvider, kind: FetchKind) -> Bool {
        // Claude quota: 30s minimum (user-initiated), 60s (background)
        // Codex quota: same
        // Cost scan: 10s minimum (FSEvents-triggered), 300s (timer)
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
| 5 | Codex counter reset token loss | 4.3 (monotonicity check detects resets) |
| 7 | Unstable `String(describing:)` for file identity | 4.2 (inode-based identity) |
| 8 | Date-range pruning evicts valid cache | 4.2 (fingerprint-based cache, no range pruning) |
| 9 | Deduplication fails with nil messageId/requestId | 4.3 (three-layer deduplication) |
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

**Phase 1:** Add FSEventsWatcher and ContentFingerprintedIncrementalParser alongside existing code. Wire FSEvents into cost scanning but keep the existing timer as primary.

**Phase 2:** Add PricingResolver. Replace hardcoded pricing lookups with resolver calls. Keep hardcoded table as Layer 5 fallback.

**Phase 3:** Add three-layer deduplication to CostUsageScanner+Claude.swift. This is a drop-in replacement for the existing dedup logic.

**Phase 4:** Add SystemLifecycleObserver and AdaptiveRefreshTimer. Replace the fixed `Task.sleep` loops in UsageStore.

**Phase 5:** Add DataPipeline coordinator. Rewire UsageStore to consume `AsyncStream<PipelineEvent>` instead of calling fetchers directly. Remove old refresh orchestration code.

**Phase 6:** Remove dead code — old polling loops, old file enumeration in cost scanner (except as P3 safety net), old hardcoded pricing (except as Layer 5 fallback).

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
| API calls per hour (active use) | < 30 | ~12 (fixed) |
| API calls per hour (idle) | < 2 | ~12 (fixed, same regardless of activity) |
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

2. **Should we persist the pricing disk cache across app updates?** If so, the cache directory should be version-independent. If not, each update gets fresh embedded data and re-fetches on first launch.

3. **Should FSEvents watch `~/.codex/archived_sessions/` too?** These are old sessions unlikely to change, but the cost scanner currently enumerates them. Watching them adds minimal overhead.
