import AppKit
import CodexBarCore
import Foundation
import Observation

// MARK: - Observation helpers

@MainActor
extension UsageStore {
    var menuObservationToken: Int {
        _ = self.snapshots
        _ = self.errors
        _ = self.lastFetchAttempts
        _ = self.accountSnapshots
        _ = self.tokenSnapshots
        _ = self.tokenErrors
        _ = self.tokenRefreshInFlight
        _ = self.credits
        _ = self.lastCreditsError
        _ = self.openAIDashboard
        _ = self.lastOpenAIDashboardError
        _ = self.openAIDashboardRequiresLogin
        _ = self.isRefreshing
        _ = self.refreshingProviders
        _ = self.statuses
        return 0
    }

    func observeSettingsChanges() {
        withObservationTracking {
            _ = self.settings.dataRefreshObservationToken
            for implementation in ProviderCatalog.all {
                implementation.observeSettings(self.settings)
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeSettingsChanges()
                self.startTimer()
                self.updateProviderRuntimes()
                if !self.settings.statusChecksEnabled {
                    self.statuses.removeAll()
                    self.resetStatusRefreshState()
                }
                await self.refresh()
            }
        }
    }
}

enum ProviderStatusIndicator: String {
    case none
    case minor
    case major
    case critical
    case maintenance
    case unknown

    var hasIssue: Bool {
        switch self {
        case .none: false
        default: true
        }
    }

    var label: String {
        switch self {
        case .none: "Operational"
        case .minor: "Partial outage"
        case .major: "Major outage"
        case .critical: "Critical issue"
        case .maintenance: "Maintenance"
        case .unknown: "Status unknown"
        }
    }
}

#if DEBUG
extension UsageStore {
    func _setSnapshotForTesting(_ snapshot: UsageSnapshot?, provider: UsageProvider) {
        self.snapshots[provider] = snapshot?.scoped(to: provider)
    }

    func _setTokenSnapshotForTesting(_ snapshot: CostUsageTokenSnapshot?, provider: UsageProvider) {
        self.tokenSnapshots[provider] = snapshot
    }

    func _setTokenErrorForTesting(_ error: String?, provider: UsageProvider) {
        self.tokenErrors[provider] = error
    }

    func _setErrorForTesting(_ error: String?, provider: UsageProvider) {
        self.errors[provider] = error
    }
}
#endif

struct ProviderStatus {
    let indicator: ProviderStatusIndicator
    let description: String?
    let updatedAt: Date?
}

/// Tracks consecutive failures so we can ignore a single flake when we previously had fresh data.
struct ConsecutiveFailureGate {
    private(set) var streak: Int = 0

    mutating func recordSuccess() {
        self.streak = 0
    }

    mutating func reset() {
        self.streak = 0
    }

    /// Returns true when the caller should surface the error to the UI.
    mutating func shouldSurfaceError(onFailureWithPriorData hadPriorData: Bool) -> Bool {
        self.streak += 1
        if hadPriorData, self.streak == 1 { return false }
        return true
    }
}

struct RefreshRequestOptions: Equatable {
    var forceTokenUsage: Bool = false
    var forceStatusChecks: Bool = false

    mutating func merge(_ other: Self) {
        self.forceTokenUsage = self.forceTokenUsage || other.forceTokenUsage
        self.forceStatusChecks = self.forceStatusChecks || other.forceStatusChecks
    }
}

struct StatusRefreshState: Equatable {
    private(set) var lastSuccessAt: Date?
    private(set) var backoffUntil: Date?
    private(set) var failureStreak: Int = 0

    func shouldRefresh(now: Date, ttl: TimeInterval, force: Bool) -> Bool {
        if force { return true }
        if let backoffUntil, now < backoffUntil { return false }
        guard let lastSuccessAt else { return true }
        return now.timeIntervalSince(lastSuccessAt) >= ttl
    }

    mutating func recordSuccess(now: Date) {
        self.lastSuccessAt = now
        self.backoffUntil = nil
        self.failureStreak = 0
    }

    mutating func recordFailure(now: Date, baseBackoff: TimeInterval, maxBackoff: TimeInterval) {
        self.failureStreak += 1
        let exponent = Double(max(0, self.failureStreak - 1))
        let delay = min(maxBackoff, baseBackoff * pow(2, exponent))
        self.backoffUntil = now.addingTimeInterval(delay)
    }

    mutating func reset() {
        self.lastSuccessAt = nil
        self.backoffUntil = nil
        self.failureStreak = 0
    }
}

struct ProviderRefreshFailureResolution: Equatable {
    let keepSnapshot: Bool
    let shouldSurfaceError: Bool

    static func resolve(hadPriorData: Bool, failureGate: inout ConsecutiveFailureGate) -> Self {
        let shouldSurfaceError = failureGate.shouldSurfaceError(onFailureWithPriorData: hadPriorData)
        return Self(
            keepSnapshot: hadPriorData,
            shouldSurfaceError: shouldSurfaceError)
    }
}

@MainActor
@Observable
final class UsageStore {
    var snapshots: [UsageProvider: UsageSnapshot] = [:]
    var errors: [UsageProvider: String] = [:]
    var lastSourceLabels: [UsageProvider: String] = [:]
    var lastFetchAttempts: [UsageProvider: [ProviderFetchAttempt]] = [:]
    var accountSnapshots: [UsageProvider: [TokenAccountUsageSnapshot]] = [:]
    var tokenSnapshots: [UsageProvider: CostUsageTokenSnapshot] = [:]
    var tokenErrors: [UsageProvider: String] = [:]
    var tokenRefreshInFlight: Set<UsageProvider> = []
    var credits: CreditsSnapshot?
    var lastCreditsError: String?
    var openAIDashboard: OpenAIDashboardSnapshot?
    var lastOpenAIDashboardError: String?
    var openAIDashboardRequiresLogin: Bool = false
    var openAIDashboardCookieImportStatus: String?
    var openAIDashboardCookieImportDebugLog: String?
    var versions: [UsageProvider: String] = [:]
    var isRefreshing = false
    var refreshingProviders: Set<UsageProvider> = []
    var debugForceAnimation = false
    var pathDebugInfo: PathDebugSnapshot = .empty
    var statuses: [UsageProvider: ProviderStatus] = [:]
    var probeLogs: [UsageProvider: String] = [:]
    @ObservationIgnored private var lastCreditsSnapshot: CreditsSnapshot?
    @ObservationIgnored private var creditsFailureStreak: Int = 0
    @ObservationIgnored private var lastOpenAIDashboardSnapshot: OpenAIDashboardSnapshot?
    @ObservationIgnored private var lastOpenAIDashboardTargetEmail: String?
    @ObservationIgnored private var lastOpenAIDashboardCookieImportAttemptAt: Date?
    @ObservationIgnored private var lastOpenAIDashboardCookieImportEmail: String?
    @ObservationIgnored private var openAIWebAccountDidChange: Bool = false

    @ObservationIgnored let codexFetcher: UsageFetcher
    @ObservationIgnored let claudeFetcher: any ClaudeUsageFetching
    @ObservationIgnored private let costUsageFetcher: CostUsageFetcher
    @ObservationIgnored let browserDetection: BrowserDetection
    @ObservationIgnored private let registry: ProviderRegistry
    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored private let sessionQuotaNotifier: any SessionQuotaNotifying
    @ObservationIgnored private let sessionQuotaLogger = CodexBarLog.logger(LogCategories.sessionQuota)
    @ObservationIgnored private let openAIWebLogger = CodexBarLog.logger(LogCategories.openAIWeb)
    @ObservationIgnored private let tokenCostLogger = CodexBarLog.logger(LogCategories.tokenCost)
    @ObservationIgnored let augmentLogger = CodexBarLog.logger(LogCategories.augment)
    @ObservationIgnored let providerLogger = CodexBarLog.logger(LogCategories.providers)
    @ObservationIgnored private var openAIWebDebugLines: [String] = []
    @ObservationIgnored var failureGates: [UsageProvider: ConsecutiveFailureGate] = [:]
    @ObservationIgnored var tokenFailureGates: [UsageProvider: ConsecutiveFailureGate] = [:]
    @ObservationIgnored var providerSpecs: [UsageProvider: ProviderSpec] = [:]
    @ObservationIgnored let providerMetadata: [UsageProvider: ProviderMetadata]
    @ObservationIgnored var providerRuntimes: [UsageProvider: any ProviderRuntime] = [:]
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var tokenTimerTask: Task<Void, Never>?
    @ObservationIgnored private var tokenRefreshSequenceTask: Task<Void, Never>?
    @ObservationIgnored private var pathDebugRefreshTask: Task<Void, Never>?
    @ObservationIgnored var lastKnownSessionRemaining: [UsageProvider: Double] = [:]
    @ObservationIgnored var lastKnownSessionWindowSource: [UsageProvider: SessionQuotaWindowSource] = [:]
    @ObservationIgnored var lastTokenFetchAt: [UsageProvider: Date] = [:]
    @ObservationIgnored private var statusRefreshStates: [UsageProvider: StatusRefreshState] = [:]
    @ObservationIgnored private var pendingRefreshRequest: RefreshRequestOptions?
    @ObservationIgnored private var hasCompletedInitialRefresh: Bool = false
    @ObservationIgnored private let tokenFetchTTL: TimeInterval = 60 * 60
    @ObservationIgnored private let tokenFetchTimeout: TimeInterval = 10 * 60
    @ObservationIgnored private let statusFetchTTL: TimeInterval = 10 * 60
    @ObservationIgnored private let statusFetchBaseBackoff: TimeInterval = 60
    @ObservationIgnored private let statusFetchMaxBackoff: TimeInterval = 30 * 60

    // MARK: - Data Pipeline

    /// The data pipeline coordinator (nil until started).
    @ObservationIgnored private var pipeline: DataPipeline?

    /// The pipeline event subscription task.
    @ObservationIgnored private var pipelineSubscription: Task<Void, Never>?

    /// The FSEvents watcher for JSONL file changes.
    @ObservationIgnored private var fsEventsWatcher: FSEventsWatcher?

    /// The adaptive refresh timer.
    @ObservationIgnored private var adaptiveTimer: AdaptiveRefreshTimer?

    /// The system lifecycle observer.
    @ObservationIgnored private var systemLifecycleObserver: SystemLifecycleObserver?

    init(
        fetcher: UsageFetcher,
        browserDetection: BrowserDetection,
        claudeFetcher: (any ClaudeUsageFetching)? = nil,
        costUsageFetcher: CostUsageFetcher = CostUsageFetcher(),
        settings: SettingsStore,
        registry: ProviderRegistry = .shared,
        sessionQuotaNotifier: any SessionQuotaNotifying = SessionQuotaNotifier())
    {
        self.codexFetcher = fetcher
        self.browserDetection = browserDetection
        self.claudeFetcher = claudeFetcher ?? ClaudeUsageFetcher(browserDetection: browserDetection)
        self.costUsageFetcher = costUsageFetcher
        self.settings = settings
        self.registry = registry
        self.sessionQuotaNotifier = sessionQuotaNotifier
        self.providerMetadata = registry.metadata
        self
            .failureGates = Dictionary(
                uniqueKeysWithValues: UsageProvider.allCases
                    .map { ($0, ConsecutiveFailureGate()) })
        self.tokenFailureGates = Dictionary(
            uniqueKeysWithValues: UsageProvider.allCases
                .map { ($0, ConsecutiveFailureGate()) })
        self.statusRefreshStates = Dictionary(
            uniqueKeysWithValues: UsageProvider.allCases
                .map { ($0, StatusRefreshState()) })
        self.providerSpecs = registry.specs(
            settings: settings,
            metadata: self.providerMetadata,
            codexFetcher: fetcher,
            claudeFetcher: self.claudeFetcher,
            browserDetection: browserDetection)
        self.providerRuntimes = Dictionary(uniqueKeysWithValues: ProviderCatalog.all.compactMap { implementation in
            implementation.makeRuntime().map { (implementation.id, $0) }
        })
        self.logStartupState()
        self.bindSettings()
        self.detectVersions()
        self.updateProviderRuntimes()
        self.pathDebugInfo = PathDebugSnapshot(
            codexBinary: nil,
            claudeBinary: nil,
            geminiBinary: nil,
            effectivePATH: PathBuilder.effectivePATH(purposes: [.rpc, .tty, .nodeTooling]),
            loginShellPATH: LoginShellPathCache.shared.current?.joined(separator: ":"))
        Task { @MainActor [weak self] in
            self?.schedulePathDebugInfoRefresh()
        }
        LoginShellPathCache.shared.captureOnce { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.schedulePathDebugInfoRefresh()
            }
        }
        Task { await self.refresh() }
        self.startTimer()
        self.startTokenTimer()
        self.startPipeline()
    }

    /// Returns the login method (plan type) for the specified provider, if available.
    private func loginMethod(for provider: UsageProvider) -> String? {
        self.snapshots[provider]?.loginMethod(for: provider)
    }

    /// Returns true if the Claude account appears to be a subscription (Max, Pro, Ultra, Team).
    /// Returns false for API users or when plan cannot be determined.
    func isClaudeSubscription() -> Bool {
        Self.isSubscriptionPlan(self.loginMethod(for: .claude))
    }

    /// Determines if a login method string indicates a Claude subscription plan.
    /// Known subscription indicators: Max, Pro, Ultra, Team (case-insensitive).
    nonisolated static func isSubscriptionPlan(_ loginMethod: String?) -> Bool {
        guard let method = loginMethod?.lowercased(), !method.isEmpty else {
            return false
        }
        let subscriptionIndicators = ["max", "pro", "ultra", "team"]
        return subscriptionIndicators.contains { method.contains($0) }
    }

    func version(for provider: UsageProvider) -> String? {
        self.versions[provider]
    }

    var preferredSnapshot: UsageSnapshot? {
        for provider in self.enabledProviders() {
            if let snap = self.snapshots[provider] { return snap }
        }
        return nil
    }

    var iconStyle: IconStyle {
        let enabled = self.enabledProviders()
        if enabled.count > 1 { return .combined }
        if let provider = enabled.first {
            return self.style(for: provider)
        }
        return .codex
    }

    var isStale: Bool {
        for provider in self.enabledProviders() where self.errors[provider] != nil {
            return true
        }
        return false
    }

    func enabledProviders() -> [UsageProvider] {
        // Use cached enablement to avoid repeated UserDefaults lookups in animation ticks.
        let enabled = self.settings.enabledProvidersOrdered(metadataByProvider: self.providerMetadata)
        return enabled.filter { self.isProviderAvailable($0) }
    }

    var statusChecksEnabled: Bool {
        self.settings.statusChecksEnabled
    }

    func metadata(for provider: UsageProvider) -> ProviderMetadata {
        self.providerMetadata[provider]!
    }

    private var codexBrowserCookieOrder: BrowserCookieImportOrder {
        self.metadata(for: .codex).browserCookieOrder ?? Browser.defaultImportOrder
    }

    func snapshot(for provider: UsageProvider) -> UsageSnapshot? {
        self.snapshots[provider]
    }

    func sourceLabel(for provider: UsageProvider) -> String {
        var label = self.lastSourceLabels[provider] ?? ""
        if label.isEmpty {
            let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
            let modes = descriptor.fetchPlan.sourceModes
            if modes.count == 1, let mode = modes.first {
                label = mode.rawValue
            } else {
                let context = ProviderSourceLabelContext(
                    provider: provider,
                    settings: self.settings,
                    store: self,
                    descriptor: descriptor)
                label = ProviderCatalog.implementation(for: provider)?
                    .defaultSourceLabel(context: context)
                    ?? "auto"
            }
        }

        let context = ProviderSourceLabelContext(
            provider: provider,
            settings: self.settings,
            store: self,
            descriptor: ProviderDescriptorRegistry.descriptor(for: provider))
        return ProviderCatalog.implementation(for: provider)?
            .decorateSourceLabel(context: context, baseLabel: label)
            ?? label
    }

    func fetchAttempts(for provider: UsageProvider) -> [ProviderFetchAttempt] {
        self.lastFetchAttempts[provider] ?? []
    }

    func style(for provider: UsageProvider) -> IconStyle {
        self.providerSpecs[provider]?.style ?? .codex
    }

    func isStale(provider: UsageProvider) -> Bool {
        self.errors[provider] != nil
    }

    func isEnabled(_ provider: UsageProvider) -> Bool {
        let enabled = self.settings.isProviderEnabledCached(
            provider: provider,
            metadataByProvider: self.providerMetadata)
        guard enabled else { return false }
        return self.isProviderAvailable(provider)
    }

    func isProviderAvailable(_ provider: UsageProvider) -> Bool {
        // Availability should mirror the effective fetch environment, including token-account overrides.
        // Otherwise providers (notably token-account-backed API providers) can fetch successfully but be
        // hidden from the menu because their credentials are not in ProcessInfo's environment.
        let environment = ProviderRegistry.makeEnvironment(
            base: ProcessInfo.processInfo.environment,
            provider: provider,
            settings: self.settings,
            tokenOverride: nil)
        let context = ProviderAvailabilityContext(
            provider: provider,
            settings: self.settings,
            environment: environment)
        return ProviderCatalog.implementation(for: provider)?
            .isAvailable(context: context)
            ?? true
    }

    func performRuntimeAction(_ action: ProviderRuntimeAction, for provider: UsageProvider) async {
        guard let runtime = self.providerRuntimes[provider] else { return }
        let context = ProviderRuntimeContext(provider: provider, settings: self.settings, store: self)
        await runtime.perform(action: action, context: context)
    }

    private func updateProviderRuntimes() {
        for (provider, runtime) in self.providerRuntimes {
            let context = ProviderRuntimeContext(provider: provider, settings: self.settings, store: self)
            if self.isEnabled(provider) {
                runtime.start(context: context)
            } else {
                runtime.stop(context: context)
            }
            runtime.settingsDidChange(context: context)
        }
    }

    func refresh(forceTokenUsage: Bool = false, forceStatusChecks: Bool = false) async {
        let requested = RefreshRequestOptions(
            forceTokenUsage: forceTokenUsage,
            forceStatusChecks: forceStatusChecks)
        if self.isRefreshing {
            self.enqueueRefresh(requested)
            return
        }

        var nextRequest: RefreshRequestOptions? = requested
        while let request = nextRequest {
            self.pendingRefreshRequest = nil
            await self.performRefresh(request)
            nextRequest = self.pendingRefreshRequest
        }
    }

    private func performRefresh(_ request: RefreshRequestOptions) async {
        let refreshPhase: ProviderRefreshPhase = self.hasCompletedInitialRefresh ? .regular : .startup
        let enabledProviders = Set(self.enabledProviders())
        let statusChecksEnabled = self.settings.statusChecksEnabled
        let now = Date()

        await ProviderRefreshContext.$current.withValue(refreshPhase) {
            self.isRefreshing = true
            defer {
                self.isRefreshing = false
                self.hasCompletedInitialRefresh = true
            }

            if !statusChecksEnabled {
                self.statuses.removeAll()
                self.resetStatusRefreshState()
            }

            await withTaskGroup(of: Void.self) { group in
                for provider in UsageProvider.allCases {
                    group.addTask { await self.refreshProvider(provider) }
                    if statusChecksEnabled,
                       enabledProviders.contains(provider),
                       self.shouldRefreshStatus(provider, now: now, force: request.forceStatusChecks)
                    {
                        group.addTask { await self.refreshStatus(provider, now: now) }
                    } else if !enabledProviders.contains(provider) {
                        self.statuses.removeValue(forKey: provider)
                        self.resetStatusRefreshState(for: provider)
                    }
                }
                group.addTask { await self.refreshCreditsIfNeeded() }
            }

            // Token-cost usage can be slow; run it outside the refresh group so we don't block menu updates.
            self.scheduleTokenRefresh(force: request.forceTokenUsage)

            // OpenAI web scrape depends on the current Codex account email (which can change after login/account
            // switch). Run this after Codex usage refresh so we don't accidentally scrape with stale credentials.
            await self.refreshOpenAIDashboardIfNeeded(force: request.forceTokenUsage)

            if self.openAIDashboardRequiresLogin {
                await self.refreshProvider(.codex)
                await self.refreshCreditsIfNeeded()
            }
        }
    }

    private func enqueueRefresh(_ request: RefreshRequestOptions) {
        if var pendingRefreshRequest = self.pendingRefreshRequest {
            pendingRefreshRequest.merge(request)
            self.pendingRefreshRequest = pendingRefreshRequest
        } else {
            self.pendingRefreshRequest = request
        }
    }

    /// For demo/testing: drop the snapshot so the loading animation plays, then restore the last snapshot.
    func replayLoadingAnimation(duration: TimeInterval = 3) {
        let current = self.preferredSnapshot
        self.snapshots.removeAll()
        self.debugForceAnimation = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            if let current, let provider = self.enabledProviders().first {
                self.snapshots[provider] = current
            }
            self.debugForceAnimation = false
        }
    }

    // MARK: - Private

    private func bindSettings() {
        self.observeSettingsChanges()
    }

    private func startTimer() {
        self.timerTask?.cancel()
        guard let wait = self.settings.refreshFrequency.seconds else { return }

        // Background poller so the menu stays responsive; canceled when settings change or store deallocates.
        self.timerTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(wait))
                await self?.refresh()
            }
        }
    }

    private func startTokenTimer() {
        self.tokenTimerTask?.cancel()
        let wait = self.tokenFetchTTL
        self.tokenTimerTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(wait))
                await self?.scheduleTokenRefresh(force: false)
            }
        }
    }

    private func scheduleTokenRefresh(force: Bool) {
        if force {
            self.tokenRefreshSequenceTask?.cancel()
            self.tokenRefreshSequenceTask = nil
        } else if self.tokenRefreshSequenceTask != nil {
            return
        }

        self.tokenRefreshSequenceTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.tokenRefreshSequenceTask = nil
                }
            }
            for provider in UsageProvider.allCases {
                if Task.isCancelled { break }
                await self.refreshTokenUsage(provider, force: force)
            }
        }
    }

    // MARK: - Data Pipeline Integration

    /// Subscribe to the DataPipeline event stream and update UI state reactively.
    private func subscribeToPipeline() {
        guard let pipeline else { return }
        pipelineSubscription?.cancel()
        pipelineSubscription = Task { [weak self] in
            let events = pipeline.events
            for await event in events {
                guard let self else { return }
                switch event {
                case .quotaUpdated(let provider, let snapshot):
                    self.snapshots[provider] = snapshot
                    self.errors[provider] = nil
                case .costUpdated(let provider, let costSnapshot):
                    self.tokenSnapshots[provider] = costSnapshot
                    self.tokenErrors[provider] = nil
                case .error(let provider, let error):
                    // Only surface errors if we don't have cached data
                    if self.snapshots[provider] == nil {
                        self.errors[provider] = error.localizedDescription
                    }
                case .pricingRefreshed:
                    break // informational
                }
            }
        }
    }

    /// Start the data pipeline (called alongside the legacy timer).
    func startPipeline() {
        let pricingResolver = PricingResolver(networkEnabled: true)
        let pipeline = DataPipeline(pricingResolver: pricingResolver)
        self.pipeline = pipeline
        subscribeToPipeline()

        // 1. FSEvents watcher
        let watcher = FSEventsWatcher()
        self.fsEventsWatcher = watcher
        let adaptiveTimer = AdaptiveRefreshTimer()
        self.adaptiveTimer = adaptiveTimer

        Task {
            // Determine watch directories
            let homeDir = URL(fileURLWithPath: NSHomeDirectory())
            var watchDirs: [(url: URL, fileExtensions: Set<String>)] = []

            let claudeProjects = homeDir.appending(path: ".claude/projects")
            if FileManager.default.fileExists(atPath: claudeProjects.path) {
                watchDirs.append((url: claudeProjects, fileExtensions: ["jsonl"]))
            }
            let codexSessions = homeDir.appending(path: ".codex/sessions")
            if FileManager.default.fileExists(atPath: codexSessions.path) {
                watchDirs.append((url: codexSessions, fileExtensions: ["jsonl"]))
            }

            guard !watchDirs.isEmpty else { return }

            let stream = await watcher.watch(
                directories: watchDirs,
                coalescingLatency: 2.0
            )

            // FSEvents -> pipeline bridge
            for await batch in stream {
                let hasJsonl = batch.contains { $0.path.hasSuffix(".jsonl") }
                if hasJsonl {
                    await adaptiveTimer.recordFSEvent()
                    await pipeline.enqueue(RefreshRequest(
                        forceTokenUsage: true,
                        priority: .p1
                    ))
                }
            }
        }

        // 2. Adaptive polling loop
        Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                await adaptiveTimer.evaluateState()
                let interval = await adaptiveTimer.currentInterval
                try? await Task.sleep(for: interval)
                let paused = await adaptiveTimer.isPaused
                guard !paused else { continue }
                guard self != nil else { return }
                await pipeline.enqueue(RefreshRequest(priority: .p2))
            }
        }

        // 3. System lifecycle observer
        let lifecycle = SystemLifecycleObserver(
            onWake: { [weak pipeline, weak adaptiveTimer] _ in
                await pipeline?.enqueue(RefreshRequest(
                    forceQuota: true,
                    forceTokenUsage: true,
                    priority: .p0
                ))
                await adaptiveTimer?.resume()
            },
            onSleep: { [weak pipeline, weak adaptiveTimer] in
                await pipeline?.cancelInFlightRequests()
                await adaptiveTimer?.pause()
            },
            onSpaceChange: { }  // Panel dismiss handled elsewhere
        )
        lifecycle.start()
        self.systemLifecycleObserver = lifecycle
    }

    /// Stop the data pipeline.
    func stopPipeline() {
        pipelineSubscription?.cancel()
        pipelineSubscription = nil

        if let pipeline {
            Task { await pipeline.shutdown() }
        }
        pipeline = nil

        if let watcher = fsEventsWatcher {
            Task { await watcher.stopAll() }
        }
        fsEventsWatcher = nil

        systemLifecycleObserver?.stop()
        systemLifecycleObserver = nil

        adaptiveTimer = nil
    }

    /// Enqueue a user-initiated refresh into the pipeline.
    func refreshViaPipeline() {
        guard let pipeline else { return }
        Task {
            await pipeline.enqueue(RefreshRequest(
                forceQuota: true,
                forceTokenUsage: true,
                priority: .p0
            ))
        }
    }

    deinit {
        self.timerTask?.cancel()
        self.tokenTimerTask?.cancel()
        self.tokenRefreshSequenceTask?.cancel()
        self.pipelineSubscription?.cancel()
    }

    enum SessionQuotaWindowSource: String {
        case primary
        case copilotSecondaryFallback
    }

    private func sessionQuotaWindow(
        provider: UsageProvider,
        snapshot: UsageSnapshot) -> (window: RateWindow, source: SessionQuotaWindowSource)?
    {
        if let primary = snapshot.primary {
            return (primary, .primary)
        }
        if provider == .copilot, let secondary = snapshot.secondary {
            return (secondary, .copilotSecondaryFallback)
        }
        return nil
    }

    func handleSessionQuotaTransition(provider: UsageProvider, snapshot: UsageSnapshot) {
        // Session quota notifications are tied to the primary session window. Copilot free plans can
        // expose only chat quota, so allow Copilot to fall back to secondary for transition tracking.
        guard let sessionWindow = self.sessionQuotaWindow(provider: provider, snapshot: snapshot) else {
            self.lastKnownSessionRemaining.removeValue(forKey: provider)
            self.lastKnownSessionWindowSource.removeValue(forKey: provider)
            return
        }
        let currentRemaining = sessionWindow.window.remainingPercent
        let currentSource = sessionWindow.source
        let previousRemaining = self.lastKnownSessionRemaining[provider]
        let previousSource = self.lastKnownSessionWindowSource[provider]

        if let previousSource, previousSource != currentSource {
            let providerText = provider.rawValue
            self.sessionQuotaLogger.debug(
                "session window source changed: provider=\(providerText) prevSource=\(previousSource.rawValue) " +
                    "currSource=\(currentSource.rawValue) curr=\(currentRemaining)")
            self.lastKnownSessionRemaining[provider] = currentRemaining
            self.lastKnownSessionWindowSource[provider] = currentSource
            return
        }

        defer {
            self.lastKnownSessionRemaining[provider] = currentRemaining
            self.lastKnownSessionWindowSource[provider] = currentSource
        }

        guard self.settings.sessionQuotaNotificationsEnabled else {
            if SessionQuotaNotificationLogic.isDepleted(currentRemaining) ||
                SessionQuotaNotificationLogic.isDepleted(previousRemaining)
            {
                let providerText = provider.rawValue
                let message =
                    "notifications disabled: provider=\(providerText) " +
                    "prev=\(previousRemaining ?? -1) curr=\(currentRemaining)"
                self.sessionQuotaLogger.debug(message)
            }
            return
        }

        guard previousRemaining != nil else {
            if SessionQuotaNotificationLogic.isDepleted(currentRemaining) {
                let providerText = provider.rawValue
                let message = "startup depleted: provider=\(providerText) curr=\(currentRemaining)"
                self.sessionQuotaLogger.info(message)
                self.sessionQuotaNotifier.post(transition: .depleted, provider: provider, badge: nil)
            }
            return
        }

        let transition = SessionQuotaNotificationLogic.transition(
            previousRemaining: previousRemaining,
            currentRemaining: currentRemaining)
        guard transition != .none else {
            if SessionQuotaNotificationLogic.isDepleted(currentRemaining) ||
                SessionQuotaNotificationLogic.isDepleted(previousRemaining)
            {
                let providerText = provider.rawValue
                let message =
                    "no transition: provider=\(providerText) " +
                    "prev=\(previousRemaining ?? -1) curr=\(currentRemaining)"
                self.sessionQuotaLogger.debug(message)
            }
            return
        }

        let providerText = provider.rawValue
        let transitionText = String(describing: transition)
        let message =
            "transition \(transitionText): provider=\(providerText) " +
            "prev=\(previousRemaining ?? -1) curr=\(currentRemaining)"
        self.sessionQuotaLogger.info(message)

        self.sessionQuotaNotifier.post(transition: transition, provider: provider, badge: nil)
    }

    private func shouldRefreshStatus(_ provider: UsageProvider, now: Date, force: Bool) -> Bool {
        if force { return true }
        return self.statusRefreshStates[provider, default: StatusRefreshState()]
            .shouldRefresh(now: now, ttl: self.statusFetchTTL, force: false)
    }

    func resetStatusRefreshState(for provider: UsageProvider? = nil) {
        if let provider {
            self.statusRefreshStates[provider]?.reset()
            return
        }
        for key in Array(self.statusRefreshStates.keys) {
            self.statusRefreshStates[key]?.reset()
        }
    }

    private func refreshStatus(_ provider: UsageProvider, now: Date = Date()) async {
        guard self.settings.statusChecksEnabled else { return }
        guard self.isEnabled(provider) else {
            self.statuses.removeValue(forKey: provider)
            self.resetStatusRefreshState(for: provider)
            return
        }
        guard let meta = self.providerMetadata[provider] else { return }

        do {
            let status: ProviderStatus
            if let urlString = meta.statusPageURL, let baseURL = URL(string: urlString) {
                status = try await Self.fetchStatus(from: baseURL)
            } else if let productID = meta.statusWorkspaceProductID {
                status = try await Self.fetchWorkspaceStatus(productID: productID)
            } else {
                return
            }
            await MainActor.run {
                self.statuses[provider] = status
                self.statusRefreshStates[provider, default: StatusRefreshState()].recordSuccess(now: now)
            }
        } catch {
            // Keep the previous status to avoid flapping when the API hiccups.
            await MainActor.run {
                self.statusRefreshStates[provider, default: StatusRefreshState()].recordFailure(
                    now: now,
                    baseBackoff: self.statusFetchBaseBackoff,
                    maxBackoff: self.statusFetchMaxBackoff)
                if self.statuses[provider] == nil {
                    self.statuses[provider] = ProviderStatus(
                        indicator: .unknown,
                        description: error.localizedDescription,
                        updatedAt: nil)
                }
            }
        }
    }

    private func refreshCreditsIfNeeded() async {
        guard self.isEnabled(.codex) else { return }
        do {
            let credits = try await self.codexFetcher.loadLatestCredits(
                keepCLISessionsAlive: self.settings.debugKeepCLISessionsAlive)
            await MainActor.run {
                self.credits = credits
                self.lastCreditsError = nil
                self.lastCreditsSnapshot = credits
                self.creditsFailureStreak = 0
            }
        } catch {
            let message = error.localizedDescription
            if message.localizedCaseInsensitiveContains("data not available yet") {
                await MainActor.run {
                    if let cached = self.lastCreditsSnapshot {
                        self.credits = cached
                        self.lastCreditsError = nil
                    } else {
                        self.credits = nil
                        self.lastCreditsError = "Codex credits are still loading; will retry shortly."
                    }
                }
                return
            }

            await MainActor.run {
                self.creditsFailureStreak += 1
                if let cached = self.lastCreditsSnapshot {
                    self.credits = cached
                    let stamp = cached.updatedAt.formatted(date: .abbreviated, time: .shortened)
                    self.lastCreditsError =
                        "Last Codex credits refresh failed: \(message). Cached values from \(stamp)."
                } else {
                    self.lastCreditsError = message
                    self.credits = nil
                }
            }
        }
    }
}

extension UsageStore {
    func requestOpenAIDashboardRefreshIfStale(reason _: String) {}

    func importOpenAIDashboardBrowserCookiesNow() async {}

    func handleOpenAIWebTargetEmailChangeIfNeeded(targetEmail _: String?) {}

    private func refreshOpenAIDashboardIfNeeded(force _: Bool = false) async {
        self.resetOpenAIWebState()
    }

    private func resetOpenAIWebDebugLog(context _: String) {}

    private func logOpenAIWeb(_: String) {}

    private func importOpenAIDashboardCookiesIfNeeded(targetEmail: String?, force _: Bool) async -> String? {
        targetEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resetOpenAIWebState() {
        self.openAIDashboard = nil
        self.lastOpenAIDashboardError = nil
        self.lastOpenAIDashboardSnapshot = nil
        self.lastOpenAIDashboardTargetEmail = nil
        self.openAIDashboardRequiresLogin = false
        self.openAIDashboardCookieImportStatus = nil
        self.openAIDashboardCookieImportDebugLog = nil
        self.lastOpenAIDashboardCookieImportAttemptAt = nil
        self.lastOpenAIDashboardCookieImportEmail = nil
        self.openAIWebAccountDidChange = false
        self.openAIWebDebugLines.removeAll(keepingCapacity: false)
    }

    func codexAccountEmailForOpenAIDashboard() -> String? {
        self.snapshots[.codex]?.accountEmail(for: .codex)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension UsageStore {
    func debugDumpClaude() async {
        let fetcher = ClaudeUsageFetcher(
            browserDetection: self.browserDetection,
            dataSource: self.settings.claudeUsageDataSource,
            keepCLISessionsAlive: self.settings.debugKeepCLISessionsAlive)
        let output = await fetcher.debugRawProbe(model: "sonnet")
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("codexbar-claude-probe.txt")
        try? output.write(to: url, atomically: true, encoding: .utf8)
        await MainActor.run {
            let snippet = String(output.prefix(180)).replacingOccurrences(of: "\n", with: " ")
            self.errors[.claude] = "[Claude] \(snippet) (saved: \(url.path))"
            NSWorkspace.shared.open(url)
        }
    }

    func dumpLog(toFileFor provider: UsageProvider) async -> URL? {
        let text = await self.debugLog(for: provider)
        let filename = "codexbar-\(provider.rawValue)-probe.txt"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            _ = await MainActor.run { NSWorkspace.shared.open(url) }
            return url
        } catch {
            await MainActor.run {
                self.errors[provider] = "Failed to save log: \(error.localizedDescription)"
            }
            return nil
        }
    }

    func debugClaudeDump() async -> String {
        "Claude CLI/web probe debug is disabled in CodexBar Lite."
    }

    func debugAugmentDump() async -> String {
        await AugmentStatusProbe.latestDumps()
    }

    func debugLog(for provider: UsageProvider) async -> String {
        if let cached = self.probeLogs[provider], !cached.isEmpty {
            return cached
        }

        let claudeWebExtrasEnabled = self.settings.claudeWebExtrasEnabled
        let claudeUsageDataSource = self.settings.claudeUsageDataSource
        let claudeCookieSource = self.settings.claudeCookieSource
        let claudeCookieHeader = self.settings.claudeCookieHeader
        let keepCLISessionsAlive = self.settings.debugKeepCLISessionsAlive
        let cursorCookieSource = self.settings.cursorCookieSource
        let cursorCookieHeader = self.settings.cursorCookieHeader
        let ampCookieSource = self.settings.ampCookieSource
        let ampCookieHeader = self.settings.ampCookieHeader
        let ollamaCookieSource = self.settings.ollamaCookieSource
        let ollamaCookieHeader = self.settings.ollamaCookieHeader
        let processEnvironment = ProcessInfo.processInfo.environment
        let openRouterConfigToken = self.settings.providerConfig(for: .openrouter)?.sanitizedAPIKey
        let openRouterHasConfigToken = !(openRouterConfigToken?.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ?? true)
        let openRouterHasEnvToken = OpenRouterSettingsReader.apiToken(environment: processEnvironment) != nil
        let openRouterEnvironment = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: processEnvironment,
            provider: .openrouter,
            config: self.settings.providerConfig(for: .openrouter))
        return await Task.detached(priority: .utility) { () -> String in
            let unimplementedDebugLogMessages: [UsageProvider: String] = [
                .gemini: "Gemini debug log not yet implemented",
                .antigravity: "Antigravity debug log not yet implemented",
                .opencode: "OpenCode debug log not yet implemented",
                .factory: "Droid debug log not yet implemented",
                .copilot: "Copilot debug log not yet implemented",
                .vertexai: "Vertex AI debug log not yet implemented",
                .kiro: "Kiro debug log not yet implemented",
                .kimi: "Kimi debug log not yet implemented",
                .kimik2: "Kimi K2 debug log not yet implemented",
                .jetbrains: "JetBrains AI debug log not yet implemented",
            ]
            let text: String
            switch provider {
            case .codex:
                text = await self.codexFetcher.debugRawRateLimits()
            case .claude:
                text = await self.debugClaudeLog(
                    claudeWebExtrasEnabled: claudeWebExtrasEnabled,
                    claudeUsageDataSource: claudeUsageDataSource,
                    claudeCookieSource: claudeCookieSource,
                    claudeCookieHeader: claudeCookieHeader,
                    keepCLISessionsAlive: keepCLISessionsAlive)
            case .zai:
                let resolution = ProviderTokenResolver.zaiResolution()
                let hasAny = resolution != nil
                let source = resolution?.source.rawValue ?? "none"
                text = "Z_AI_API_KEY=\(hasAny ? "present" : "missing") source=\(source)"
            case .synthetic:
                let resolution = ProviderTokenResolver.syntheticResolution()
                let hasAny = resolution != nil
                let source = resolution?.source.rawValue ?? "none"
                text = "SYNTHETIC_API_KEY=\(hasAny ? "present" : "missing") source=\(source)"
            case .cursor:
                text = await self.debugCursorLog(
                    cursorCookieSource: cursorCookieSource,
                    cursorCookieHeader: cursorCookieHeader)
            case .minimax:
                let tokenResolution = ProviderTokenResolver.minimaxTokenResolution()
                let cookieResolution = ProviderTokenResolver.minimaxCookieResolution()
                let tokenSource = tokenResolution?.source.rawValue ?? "none"
                let cookieSource = cookieResolution?.source.rawValue ?? "none"
                text = "MINIMAX_API_KEY=\(tokenResolution == nil ? "missing" : "present") " +
                    "source=\(tokenSource) MINIMAX_COOKIE=\(cookieResolution == nil ? "missing" : "present") " +
                    "source=\(cookieSource)"
            case .augment:
                text = await self.debugAugmentLog()
            case .amp:
                text = await self.debugAmpLog(
                    ampCookieSource: ampCookieSource,
                    ampCookieHeader: ampCookieHeader)
            case .ollama:
                text = await self.debugOllamaLog(
                    ollamaCookieSource: ollamaCookieSource,
                    ollamaCookieHeader: ollamaCookieHeader)
            case .openrouter:
                let resolution = ProviderTokenResolver.openRouterResolution(environment: openRouterEnvironment)
                let hasAny = resolution != nil
                let source: String = if resolution == nil {
                    "none"
                } else if openRouterHasConfigToken, openRouterHasEnvToken {
                    "settings-config (overrides env)"
                } else if openRouterHasConfigToken {
                    "settings-config"
                } else {
                    resolution?.source.rawValue ?? "environment"
                }
                text = "OPENROUTER_API_KEY=\(hasAny ? "present" : "missing") source=\(source)"
            case .warp:
                let resolution = ProviderTokenResolver.warpResolution()
                let hasAny = resolution != nil
                let source = resolution?.source.rawValue ?? "none"
                text = "WARP_API_KEY=\(hasAny ? "present" : "missing") source=\(source)"
            case .gemini, .antigravity, .opencode, .factory, .copilot, .vertexai, .kiro, .kimi, .kimik2, .jetbrains:
                text = unimplementedDebugLogMessages[provider] ?? "Debug log not yet implemented"
            }

            await MainActor.run { self.probeLogs[provider] = text }
            return text
        }.value
    }

    private func debugClaudeLog(
        claudeWebExtrasEnabled: Bool,
        claudeUsageDataSource: ClaudeUsageDataSource,
        claudeCookieSource: ProviderCookieSource,
        claudeCookieHeader: String,
        keepCLISessionsAlive: Bool) async -> String
    {
        struct OAuthDebugProbe: Sendable {
            let hasCredentials: Bool
            let ownerRawValue: String
            let sourceRawValue: String
            let isExpired: Bool
        }

        return await self.runWithTimeout(seconds: 15) {
            var lines: [String] = []
            let manualHeader = claudeCookieSource == .manual
                ? CookieHeaderNormalizer.normalize(claudeCookieHeader)
                : nil
            let hasKey = if let manualHeader {
                ClaudeWebAPIFetcher.hasSessionKey(cookieHeader: manualHeader)
            } else {
                ClaudeWebAPIFetcher.hasSessionKey(browserDetection: self.browserDetection) { msg in lines.append(msg) }
            }
            // Run potentially blocking keychain probes off MainActor so debug dumps don't stall UI rendering.
            let oauthProbe = await Task.detached(priority: .utility) {
                // Don't prompt for keychain access during debug dump.
                let oauthRecord = try? ClaudeOAuthCredentialsStore.loadRecord(
                    allowKeychainPrompt: false,
                    respectKeychainPromptCooldown: true,
                    allowClaudeKeychainRepairWithoutPrompt: false)
                return OAuthDebugProbe(
                    hasCredentials: oauthRecord?.credentials.scopes.contains("user:profile") == true,
                    ownerRawValue: oauthRecord?.owner.rawValue ?? "none",
                    sourceRawValue: oauthRecord?.source.rawValue ?? "none",
                    isExpired: oauthRecord?.credentials.isExpired ?? false)
            }.value
            let hasOAuthCredentials = oauthProbe.hasCredentials
            let hasClaudeBinary = ClaudeOAuthDelegatedRefreshCoordinator.isClaudeCLIAvailable()
            let delegatedCooldownSeconds = ClaudeOAuthDelegatedRefreshCoordinator.cooldownRemainingSeconds()

            let strategy = ClaudeProviderDescriptor.resolveUsageStrategy(
                selectedDataSource: claudeUsageDataSource,
                webExtrasEnabled: claudeWebExtrasEnabled,
                hasWebSession: hasKey,
                hasCLI: hasClaudeBinary,
                hasOAuthCredentials: hasOAuthCredentials)

            if claudeUsageDataSource == .auto {
                lines.append("pipeline_order=claude-code→local")
                lines.append("auto_heuristic=live_with_auth_fallback")
            } else {
                lines.append("strategy=\(strategy.dataSource.rawValue)")
            }
            lines.append("hasSessionKey=\(hasKey)")
            lines.append("hasOAuthCredentials=\(hasOAuthCredentials)")
            lines.append("oauthCredentialOwner=\(oauthProbe.ownerRawValue)")
            lines.append("oauthCredentialSource=\(oauthProbe.sourceRawValue)")
            lines.append("oauthCredentialExpired=\(oauthProbe.isExpired)")
            lines.append("delegatedRefreshCLIAvailable=\(hasClaudeBinary)")
            lines.append("delegatedRefreshCooldownActive=\(delegatedCooldownSeconds != nil)")
            if let delegatedCooldownSeconds {
                lines.append("delegatedRefreshCooldownSeconds=\(delegatedCooldownSeconds)")
            }
            lines.append("hasClaudeBinary=\(hasClaudeBinary)")
            if strategy.useWebExtras {
                lines.append("web_extras=enabled")
            }
            lines.append("")

            switch strategy.dataSource {
            case .auto:
                let fetcher = ClaudeUsageFetcher(
                    browserDetection: self.browserDetection,
                    dataSource: .auto,
                    keepCLISessionsAlive: keepCLISessionsAlive)
                await lines.append(fetcher.debugRawProbe(model: "sonnet"))
                return lines.joined(separator: "\n")
            case .web:
                lines.append("Web source is disabled in Lite; using automatic Claude Code probing.")
                let fetcher = ClaudeUsageFetcher(
                    browserDetection: self.browserDetection,
                    dataSource: .auto,
                    keepCLISessionsAlive: keepCLISessionsAlive)
                await lines.append(fetcher.debugRawProbe(model: "sonnet"))
                return lines.joined(separator: "\n")
            case .cli:
                let fetcher = ClaudeUsageFetcher(
                    browserDetection: self.browserDetection,
                    dataSource: .auto,
                    keepCLISessionsAlive: keepCLISessionsAlive)
                let cli = await fetcher.debugRawProbe(model: "sonnet")
                lines.append(cli)
                return lines.joined(separator: "\n")
            case .oauth:
                lines.append("Claude Code live source selected.")
                let fetcher = ClaudeUsageFetcher(
                    browserDetection: self.browserDetection,
                    dataSource: .oauth,
                    keepCLISessionsAlive: keepCLISessionsAlive)
                await lines.append(fetcher.debugRawProbe(model: "sonnet"))
                return lines.joined(separator: "\n")
            }
        }
    }

    private func debugCursorLog(
        cursorCookieSource: ProviderCookieSource,
        cursorCookieHeader: String) async -> String
    {
        await self.runWithTimeout(seconds: 15) {
            var lines: [String] = []

            do {
                let probe = CursorStatusProbe(browserDetection: self.browserDetection)
                let snapshot: CursorStatusSnapshot = if cursorCookieSource == .manual,
                                                        let normalizedHeader = CookieHeaderNormalizer
                                                            .normalize(cursorCookieHeader)
                {
                    try await probe.fetchWithManualCookies(normalizedHeader)
                } else {
                    try await probe.fetch { msg in lines.append("[cursor-cookie] \(msg)") }
                }

                lines.append("")
                lines.append("Cursor Status Summary:")
                lines.append("membershipType=\(snapshot.membershipType ?? "nil")")
                lines.append("accountEmail=\(snapshot.accountEmail ?? "nil")")
                lines.append("planPercentUsed=\(snapshot.planPercentUsed)%")
                lines.append("planUsedUSD=$\(snapshot.planUsedUSD)")
                lines.append("planLimitUSD=$\(snapshot.planLimitUSD)")
                lines.append("onDemandUsedUSD=$\(snapshot.onDemandUsedUSD)")
                lines.append("onDemandLimitUSD=\(snapshot.onDemandLimitUSD.map { "$\($0)" } ?? "nil")")
                if let teamUsed = snapshot.teamOnDemandUsedUSD {
                    lines.append("teamOnDemandUsedUSD=$\(teamUsed)")
                }
                if let teamLimit = snapshot.teamOnDemandLimitUSD {
                    lines.append("teamOnDemandLimitUSD=$\(teamLimit)")
                }
                lines.append("billingCycleEnd=\(snapshot.billingCycleEnd?.description ?? "nil")")

                if let rawJSON = snapshot.rawJSON {
                    lines.append("")
                    lines.append("Raw API Response:")
                    lines.append(rawJSON)
                }

                return lines.joined(separator: "\n")
            } catch {
                lines.append("")
                lines.append("Cursor probe failed: \(error.localizedDescription)")
                return lines.joined(separator: "\n")
            }
        }
    }

    private func debugAugmentLog() async -> String {
        await self.runWithTimeout(seconds: 15) {
            let probe = AugmentStatusProbe()
            return await probe.debugRawProbe()
        }
    }

    private func debugAmpLog(
        ampCookieSource: ProviderCookieSource,
        ampCookieHeader: String) async -> String
    {
        await self.runWithTimeout(seconds: 15) {
            let fetcher = AmpUsageFetcher(browserDetection: self.browserDetection)
            let manualHeader = ampCookieSource == .manual
                ? CookieHeaderNormalizer.normalize(ampCookieHeader)
                : nil
            return await fetcher.debugRawProbe(cookieHeaderOverride: manualHeader)
        }
    }

    private func debugOllamaLog(
        ollamaCookieSource: ProviderCookieSource,
        ollamaCookieHeader: String) async -> String
    {
        await self.runWithTimeout(seconds: 15) {
            let fetcher = OllamaUsageFetcher(browserDetection: self.browserDetection)
            let manualHeader = ollamaCookieSource == .manual
                ? CookieHeaderNormalizer.normalize(ollamaCookieHeader)
                : nil
            return await fetcher.debugRawProbe(
                cookieHeaderOverride: manualHeader,
                manualCookieMode: ollamaCookieSource == .manual)
        }
    }

    private func runWithTimeout(seconds: Double, operation: @escaping @Sendable () async -> String) async -> String {
        await withTaskGroup(of: String?.self) { group -> String in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let result = await group.next()?.flatMap(\.self)
            group.cancelAll()
            return result ?? "Probe timed out after \(Int(seconds))s"
        }
    }

    private func detectVersions() {
        let implementations = ProviderCatalog.all
        let browserDetection = self.browserDetection
        Task { @MainActor [weak self] in
            let resolved = await Task.detached { () -> [UsageProvider: String] in
                var resolved: [UsageProvider: String] = [:]
                await withTaskGroup(of: (UsageProvider, String?).self) { group in
                    for implementation in implementations {
                        let context = ProviderVersionContext(
                            provider: implementation.id,
                            browserDetection: browserDetection)
                        group.addTask {
                            await (implementation.id, implementation.detectVersion(context: context))
                        }
                    }
                    for await (provider, version) in group {
                        guard let version, !version.isEmpty else { continue }
                        resolved[provider] = version
                    }
                }
                return resolved
            }.value
            self?.versions = resolved
        }
    }

    @MainActor
    private func schedulePathDebugInfoRefresh() {
        self.pathDebugRefreshTask?.cancel()
        self.pathDebugRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
            } catch {
                return
            }
            await self?.refreshPathDebugInfo()
        }
    }

    private func runBackgroundSnapshot(
        _ snapshot: @escaping @Sendable () async -> PathDebugSnapshot) async
    {
        let result = await snapshot()
        await MainActor.run {
            self.pathDebugInfo = result
        }
    }

    private func refreshPathDebugInfo() async {
        await self.runBackgroundSnapshot {
            await PathBuilder.debugSnapshotAsync(purposes: [.rpc, .tty, .nodeTooling])
        }
    }

    func clearCostUsageCache() async -> String? {
        let errorMessage: String? = await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let cacheDirs = [
                Self.costUsageCacheDirectory(fileManager: fm),
            ]

            for cacheDir in cacheDirs {
                do {
                    try fm.removeItem(at: cacheDir)
                } catch let error as NSError {
                    if error.domain == NSCocoaErrorDomain, error.code == NSFileNoSuchFileError { continue }
                    return error.localizedDescription
                }
            }
            return nil
        }.value

        guard errorMessage == nil else { return errorMessage }

        self.tokenSnapshots.removeAll()
        self.tokenErrors.removeAll()
        self.lastTokenFetchAt.removeAll()
        self.tokenFailureGates[.codex]?.reset()
        self.tokenFailureGates[.claude]?.reset()
        return nil
    }

    private func refreshTokenUsage(_ provider: UsageProvider, force: Bool) async {
        guard provider == .codex || provider == .claude || provider == .vertexai else {
            self.tokenSnapshots.removeValue(forKey: provider)
            self.tokenErrors[provider] = nil
            self.tokenFailureGates[provider]?.reset()
            self.lastTokenFetchAt.removeValue(forKey: provider)
            return
        }

        guard self.settings.costUsageEnabled else {
            self.tokenSnapshots.removeValue(forKey: provider)
            self.tokenErrors[provider] = nil
            self.tokenFailureGates[provider]?.reset()
            self.lastTokenFetchAt.removeValue(forKey: provider)
            return
        }

        guard self.isEnabled(provider) else {
            self.tokenSnapshots.removeValue(forKey: provider)
            self.tokenErrors[provider] = nil
            self.tokenFailureGates[provider]?.reset()
            self.lastTokenFetchAt.removeValue(forKey: provider)
            return
        }

        guard !self.tokenRefreshInFlight.contains(provider) else { return }

        let now = Date()
        if !force,
           let last = self.lastTokenFetchAt[provider],
           now.timeIntervalSince(last) < self.tokenFetchTTL
        {
            return
        }
        self.tokenRefreshInFlight.insert(provider)
        defer { self.tokenRefreshInFlight.remove(provider) }

        let startedAt = Date()
        let providerText = provider.rawValue
        self.tokenCostLogger
            .debug("cost usage start provider=\(providerText) force=\(force)")

        do {
            let fetcher = self.costUsageFetcher
            let timeoutSeconds = self.tokenFetchTimeout
            let snapshot = try await withThrowingTaskGroup(of: CostUsageTokenSnapshot.self) { group in
                group.addTask(priority: .utility) {
                    try await fetcher.loadTokenSnapshot(
                        provider: provider,
                        now: now,
                        forceRefresh: force,
                        allowVertexClaudeFallback: !self.isEnabled(.claude))
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    throw CostUsageError.timedOut(seconds: Int(timeoutSeconds))
                }
                defer { group.cancelAll() }
                guard let snapshot = try await group.next() else { throw CancellationError() }
                return snapshot
            }

            guard !snapshot.daily.isEmpty else {
                self.lastTokenFetchAt[provider] = Date()
                self.tokenSnapshots.removeValue(forKey: provider)
                self.tokenErrors[provider] = Self.tokenCostNoDataMessage(for: provider)
                self.tokenFailureGates[provider]?.recordSuccess()
                return
            }
            let duration = Date().timeIntervalSince(startedAt)
            let sessionCost = snapshot.sessionCostUSD.map(UsageFormatter.usdString) ?? "—"
            let monthCost = snapshot.last30DaysCostUSD.map(UsageFormatter.usdString) ?? "—"
            let durationText = String(format: "%.2f", duration)
            let message =
                "cost usage success provider=\(providerText) " +
                "duration=\(durationText)s " +
                "today=\(sessionCost) " +
                "30d=\(monthCost)"
            self.tokenCostLogger.info(message)
            self.lastTokenFetchAt[provider] = Date()
            self.tokenSnapshots[provider] = snapshot
            self.tokenErrors[provider] = nil
            self.tokenFailureGates[provider]?.recordSuccess()

        } catch {
            if error is CancellationError { return }
            let duration = Date().timeIntervalSince(startedAt)
            let msg = error.localizedDescription
            let durationText = String(format: "%.2f", duration)
            let message = "cost usage failed provider=\(providerText) duration=\(durationText)s error=\(msg)"
            self.tokenCostLogger.error(message)
            let hadPriorData = self.tokenSnapshots[provider] != nil
            let shouldSurface = self.tokenFailureGates[provider]?
                .shouldSurfaceError(onFailureWithPriorData: hadPriorData) ?? true
            if shouldSurface {
                self.tokenErrors[provider] = error.localizedDescription
                self.tokenSnapshots.removeValue(forKey: provider)
            } else {
                self.tokenErrors[provider] = nil
            }
        }
    }
}
