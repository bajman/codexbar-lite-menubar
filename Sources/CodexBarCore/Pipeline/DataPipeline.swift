// Sources/CodexBarCore/Pipeline/DataPipeline.swift
import Foundation

/// Central coordinator that accepts RefreshRequests, coalesces them,
/// limits concurrency, calls provider fetchers, and emits PipelineEvents.
actor DataPipeline {

    // MARK: - Types

    /// Events emitted by the pipeline for UsageStore consumption.
    enum PipelineEvent: Sendable {
        case quotaUpdated(UsageProvider, UsageSnapshot)
        case costUpdated(UsageProvider, CostUsageTokenSnapshot)
        case error(UsageProvider, any Error)
        case pricingRefreshed(modelCount: Int)
    }

    // MARK: - State

    private let pricingResolver: PricingResolver
    private var coalescing = CoalescingEngine()
    private let networkLimiter = ConcurrencyLimiter(limit: 2)
    private let fileScanLimiter = ConcurrencyLimiter(limit: 1)

    private var continuation: AsyncStream<PipelineEvent>.Continuation?
    private var processingTask: Task<Void, Never>?
    private var inFlightTasks: [Task<Void, Never>] = []

    /// Signal mechanism: a continuation that the processing loop awaits,
    /// and `enqueue()` resumes to wake the loop.
    private var signalContinuation: CheckedContinuation<Void, Never>?

    private var isShutDown = false
    private var isStarted = false

    private let logger = CodexBarLog.logger(LogCategories.dataPipeline)

    // MARK: - Public API

    /// The event stream. UsageStore subscribes to this.
    /// Uses .bufferingNewest(20) — stale events are dropped.
    nonisolated let events: AsyncStream<PipelineEvent>

    /// Create a pipeline. Call `start()` to begin the processing loop.
    init(pricingResolver: PricingResolver) {
        self.pricingResolver = pricingResolver

        let (stream, cont) = AsyncStream<PipelineEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(20)
        )
        self.events = stream
        self.continuation = cont
    }

    /// Start the processing loop. Safe to call multiple times (only starts once).
    func start() {
        guard !isStarted, !isShutDown else { return }
        isStarted = true
        processingTask = Task { [weak self] in
            await self?.runProcessingLoop()
        }
    }

    /// Enqueue a refresh request. The request is merged with any pending
    /// request via CoalescingEngine. Automatically starts the pipeline if needed.
    func enqueue(_ request: RefreshRequest) {
        guard !isShutDown else { return }
        if !isStarted { start() }
        coalescing.mergeRefreshRequest(request)
        logger.debug("Enqueued request priority=\(request.priority)")
        // Wake the processing loop.
        if let signal = signalContinuation {
            signalContinuation = nil
            signal.resume()
        }
    }

    /// Cancel all in-flight network requests (called on sleep).
    func cancelInFlightRequests() {
        for task in inFlightTasks {
            task.cancel()
        }
        inFlightTasks.removeAll()
        logger.info("Cancelled in-flight requests")
    }

    /// Shut down the pipeline (stop processing loop, finish event stream).
    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        processingTask?.cancel()
        processingTask = nil
        cancelInFlightRequests()
        // Wake any waiting signal so the loop can exit.
        if let signal = signalContinuation {
            signalContinuation = nil
            signal.resume()
        }
        continuation?.finish()
        continuation = nil
        logger.info("Pipeline shut down")
    }

    // MARK: - Processing Loop

    private func runProcessingLoop() async {
        while !Task.isCancelled && !isShutDown {
            // Wait for a request to arrive.
            await waitForRequest()

            guard !Task.isCancelled && !isShutDown else { break }

            // Drain the coalesced request.
            guard let request = coalescing.drainPendingRequest() else {
                continue
            }

            await processRequest(request)
        }
    }

    /// Suspends until `enqueue()` signals that a request is available.
    private func waitForRequest() async {
        // If there's already a pending request, return immediately.
        if coalescing.hasPending { return }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            signalContinuation = cont
        }
    }

    // MARK: - Request Processing

    private func processRequest(_ request: RefreshRequest) async {
        let providers = request.providers.isEmpty
            ? UsageProvider.allCases.filter { isEnabled($0) }
            : Array(request.providers)

        guard !providers.isEmpty else {
            logger.debug("No providers to refresh")
            return
        }

        logger.info("Processing request for \(providers.map(\.rawValue)) priority=\(request.priority)")

        await withTaskGroup(of: Void.self) { group in
            for provider in providers {
                group.addTask { [self] in
                    await self.refreshProvider(provider, request: request)
                }
            }
        }

        // Clean up completed in-flight tasks.
        inFlightTasks.removeAll { $0.isCancelled }
    }

    private func refreshProvider(_ provider: UsageProvider, request: RefreshRequest) async {
        // Quota refresh
        let shouldSkipQuota = !request.forceQuota && coalescing.shouldSkip(
            provider: provider, kind: .quota, priority: request.priority
        )

        if !shouldSkipQuota {
            await networkLimiter.acquire()
            do {
                let snapshot = try await fetchQuota(for: provider)
                continuation?.yield(.quotaUpdated(provider, snapshot))
                coalescing.recordCompletion(provider: provider, kind: .quota)
                logger.debug("Quota updated for \(provider.rawValue)")
            } catch {
                if !Task.isCancelled {
                    continuation?.yield(.error(provider, error))
                    logger.warning("Quota fetch failed for \(provider.rawValue): \(error)")
                }
            }
            await networkLimiter.release()
        }

        // Cost refresh (placeholder — will be fully wired in Task 15)
        if request.forceTokenUsage {
            await fileScanLimiter.acquire()
            do {
                let snapshot = try await fetchCost(for: provider)
                continuation?.yield(.costUpdated(provider, snapshot))
                coalescing.recordCompletion(provider: provider, kind: .tokenCost)
                logger.debug("Cost updated for \(provider.rawValue)")
            } catch {
                if !Task.isCancelled {
                    continuation?.yield(.error(provider, error))
                    logger.warning("Cost fetch failed for \(provider.rawValue): \(error)")
                }
            }
            await fileScanLimiter.release()
        }
    }

    // MARK: - Provider Enablement

    private nonisolated func isEnabled(_ provider: UsageProvider) -> Bool {
        switch provider {
        case .claude:
            return FileManager.default.fileExists(
                atPath: NSHomeDirectory() + "/.claude"
            )
        case .codex:
            return FileManager.default.fileExists(
                atPath: NSHomeDirectory() + "/.codex"
            )
        default:
            return false
        }
    }

    // MARK: - Fetchers

    private func fetchQuota(for provider: UsageProvider) async throws -> UsageSnapshot {
        switch provider {
        case .claude:
            let fetcher = ClaudeLiteFetcher()
            return try await fetcher.fetchUsage()
        case .codex:
            let fetcher = CodexLiteFetcher()
            return try await fetcher.fetchUsage()
        default:
            throw DataPipelineError.unsupportedProvider(provider)
        }
    }

    /// Placeholder for cost scanning — will be fully wired in Task 15.
    private func fetchCost(for provider: UsageProvider) async throws -> CostUsageTokenSnapshot {
        // For now, throw — real implementation will use
        // CostUsageScanner.loadDailyReport() and PricingResolver.
        throw DataPipelineError.costScanningNotImplemented
    }
}

// MARK: - Errors

enum DataPipelineError: LocalizedError {
    case unsupportedProvider(UsageProvider)
    case costScanningNotImplemented

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let provider):
            "Unsupported provider: \(provider.rawValue)"
        case .costScanningNotImplemented:
            "Cost scanning is not yet implemented in the pipeline."
        }
    }
}
