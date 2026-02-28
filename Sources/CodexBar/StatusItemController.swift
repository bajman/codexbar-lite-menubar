import AppKit
import CodexBarCore
import ObjectiveC
import Observation
import QuartzCore
import SwiftUI

// MARK: - Status item controller (AppKit-hosted icons, SwiftUI popovers)

@MainActor
protocol StatusItemControlling: AnyObject {
    func openMenuFromShortcut()
}

@MainActor
final class StatusItemController: NSObject, StatusItemControlling, MenuPanelActions {
    // Disable SwiftUI menu cards + menu refresh work in tests to avoid swiftpm-testing-helper crashes.
    static var menuCardRenderingEnabled = !SettingsStore.isRunningTests
    static var menuRefreshEnabled = !SettingsStore.isRunningTests
    typealias Factory = (UsageStore, SettingsStore, AccountInfo, UpdaterProviding, PreferencesSelection)
        -> StatusItemControlling
    static let defaultFactory: Factory = { store, settings, account, updater, selection in
        StatusItemController(
            store: store,
            settings: settings,
            account: account,
            updater: updater,
            preferencesSelection: selection)
    }

    static var factory: Factory = StatusItemController.defaultFactory

    let store: UsageStore
    let settings: SettingsStore
    let account: AccountInfo
    let updater: UpdaterProviding
    private let statusBar: NSStatusBar
    var statusItem: NSStatusItem
    var statusItems: [UsageProvider: NSStatusItem] = [:]
    var lastMenuProvider: UsageProvider?
    var panelController: MenuPanelController?
    var blinkTask: Task<Void, Never>?
    var loginTask: Task<Void, Never>? {
        didSet { self.refreshMenusForLoginStateChange() }
    }

    var creditsPurchaseWindow: OpenAICreditsPurchaseWindowController?

    var activeLoginProvider: UsageProvider? {
        didSet {
            if oldValue != self.activeLoginProvider {
                self.refreshMenusForLoginStateChange()
            }
        }
    }

    var blinkStates: [UsageProvider: BlinkState] = [:]
    var blinkAmounts: [UsageProvider: CGFloat] = [:]
    var wiggleAmounts: [UsageProvider: CGFloat] = [:]
    var tiltAmounts: [UsageProvider: CGFloat] = [:]
    var blinkForceUntil: Date?
    var loginPhase: LoginPhase = .idle {
        didSet {
            if oldValue != self.loginPhase {
                self.refreshMenusForLoginStateChange()
            }
        }
    }

    let preferencesSelection: PreferencesSelection
    var animationDriver: DisplayLinkDriver?
    var animationPhase: Double = 0
    var animationPattern: LoadingPattern = .knightRider
    private var lastConfigRevision: Int
    private var lastProviderOrder: [UsageProvider]
    private var lastMergeIcons: Bool
    private var lastSwitcherShowsIcons: Bool
    private var lastObservedUsageBarsShowUsed: Bool
    let loginLogger = CodexBarLog.logger(LogCategories.login)
    var selectedMenuProvider: UsageProvider? {
        get { self.settings.selectedMenuProvider }
        set { self.settings.selectedMenuProvider = newValue }
    }

    struct BlinkState {
        var nextBlink: Date
        var blinkStart: Date?
        var pendingSecondStart: Date?
        var effect: MotionEffect = .blink

        static func randomDelay() -> TimeInterval {
            Double.random(in: 3...12)
        }
    }

    enum MotionEffect {
        case blink
        case wiggle
        case tilt
    }

    enum LoginPhase {
        case idle
        case requesting
        case waitingBrowser
    }

    // MARK: - Associated-Object Provider Tagging

    private static let providerKey = malloc(1)!

    func tagButton(_ button: NSStatusBarButton, provider: UsageProvider) {
        objc_setAssociatedObject(button, Self.providerKey, provider.rawValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    func provider(for button: NSStatusBarButton) -> UsageProvider? {
        guard let raw = objc_getAssociatedObject(button, Self.providerKey) as? String else { return nil }
        return UsageProvider(rawValue: raw)
    }

    func menuBarMetricWindow(for provider: UsageProvider, snapshot: UsageSnapshot?) -> RateWindow? {
        switch self.settings.menuBarMetricPreference(for: provider) {
        case .primary:
            return snapshot?.primary ?? snapshot?.secondary
        case .secondary:
            return snapshot?.secondary ?? snapshot?.primary
        case .average:
            guard let primary = snapshot?.primary, let secondary = snapshot?.secondary else {
                return snapshot?.primary ?? snapshot?.secondary
            }
            let usedPercent = (primary.usedPercent + secondary.usedPercent) / 2
            return RateWindow(usedPercent: usedPercent, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        case .automatic:
            if provider == .factory || provider == .kimi {
                return snapshot?.secondary ?? snapshot?.primary
            }
            if provider == .copilot,
               let primary = snapshot?.primary,
               let secondary = snapshot?.secondary
            {
                // Copilot can expose chat + completions quotas; show the more constrained one by default.
                return primary.usedPercent >= secondary.usedPercent ? primary : secondary
            }
            return snapshot?.primary ?? snapshot?.secondary
        }
    }

    init(
        store: UsageStore,
        settings: SettingsStore,
        account: AccountInfo,
        updater: UpdaterProviding,
        preferencesSelection: PreferencesSelection,
        statusBar: NSStatusBar = .system)
    {
        if SettingsStore.isRunningTests {
            _ = NSApplication.shared
        }
        self.store = store
        self.settings = settings
        self.account = account
        self.updater = updater
        self.preferencesSelection = preferencesSelection
        self.lastConfigRevision = settings.configRevision
        self.lastProviderOrder = settings.providerOrder
        self.lastMergeIcons = settings.mergeIcons
        self.lastSwitcherShowsIcons = settings.switcherShowsIcons
        self.lastObservedUsageBarsShowUsed = settings.usageBarsShowUsed
        self.statusBar = statusBar
        let item = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        // Ensure the icon is rendered at 1:1 without resampling (crisper edges for template images).
        item.button?.imageScaling = .scaleNone
        self.statusItem = item
        // Set a placeholder icon immediately so the status item is visible from the first frame,
        // even if store state is still loading.
        let placeholder = IconRenderer.makeIcon(
            primaryRemaining: nil,
            weeklyRemaining: nil,
            creditsRemaining: nil,
            stale: false,
            style: .codex,
            blink: 0,
            wiggle: 0,
            tilt: 0)
        placeholder.isTemplate = true
        item.button?.image = placeholder
        // Status items for individual providers are now created lazily in updateVisibility()
        super.init()
        self.wireBindings()
        self.updateIcons()
        self.updateVisibility()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.handleDebugReplayNotification(_:)),
            name: .codexbarDebugReplayAllAnimations,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.handleDebugBlinkNotification),
            name: .codexbarDebugBlinkNow,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.handleProviderConfigDidChange),
            name: .codexbarProviderConfigDidChange,
            object: nil)
    }

    private func wireBindings() {
        self.observeStoreChanges()
        self.observeDebugForceAnimation()
        self.observeSettingsChanges()
        self.observeUpdaterChanges()
    }

    private func observeStoreChanges() {
        withObservationTracking {
            _ = self.store.menuObservationToken
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeStoreChanges()
                self.invalidateMenus()
                self.updateIcons()
                self.updateBlinkingState()
            }
        }
    }

    private func observeDebugForceAnimation() {
        withObservationTracking {
            _ = self.store.debugForceAnimation
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeDebugForceAnimation()
                self.updateVisibility()
                self.updateBlinkingState()
            }
        }
    }

    private func observeSettingsChanges() {
        withObservationTracking {
            _ = self.settings.menuObservationToken
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeSettingsChanges()
                self.handleSettingsChange(reason: "observation")
            }
        }
    }

    func handleProviderConfigChange(reason: String) {
        self.handleSettingsChange(reason: "config:\(reason)")
    }

    @objc private func handleProviderConfigDidChange(_ notification: Notification) {
        let reason = notification.userInfo?["reason"] as? String ?? "unknown"
        if let source = notification.object as? SettingsStore,
           source !== self.settings
        {
            if let config = notification.userInfo?["config"] as? CodexBarConfig {
                self.settings.applyExternalConfig(config, reason: "external-\(reason)")
            } else {
                self.settings.reloadConfig(reason: "external-\(reason)")
            }
        }
        self.handleProviderConfigChange(reason: "notification:\(reason)")
    }

    private func observeUpdaterChanges() {
        withObservationTracking {
            _ = self.updater.updateStatus.isUpdateReady
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeUpdaterChanges()
                self.invalidateMenus()
            }
        }
    }

    private func invalidateMenus() {
        // SwiftUI observes store changes automatically — no manual menu rebuild needed
    }

    private func handleSettingsChange(reason: String) {
        let configChanged = self.settings.configRevision != self.lastConfigRevision
        let orderChanged = self.settings.providerOrder != self.lastProviderOrder
        if self.settings.configRevision != self.lastConfigRevision {
            self.lastConfigRevision = self.settings.configRevision
        }
        if self.settings.providerOrder != self.lastProviderOrder {
            self.lastProviderOrder = self.settings.providerOrder
        }
        if self.settings.mergeIcons != self.lastMergeIcons {
            let wasMerged = self.lastMergeIcons
            self.lastMergeIcons = self.settings.mergeIcons
            // When switching from merged → split-icon mode, clear the stale
            // selectedMenuProvider so it doesn't override per-icon clicks.
            if wasMerged, !self.settings.mergeIcons {
                self.selectedMenuProvider = nil
                self.lastMenuProvider = nil
            }
        }
        if self.settings.switcherShowsIcons != self.lastSwitcherShowsIcons {
            self.lastSwitcherShowsIcons = self.settings.switcherShowsIcons
        }
        if self.settings.usageBarsShowUsed != self.lastObservedUsageBarsShowUsed {
            self.lastObservedUsageBarsShowUsed = self.settings.usageBarsShowUsed
        }
        if orderChanged || configChanged {
            self.rebuildProviderStatusItems()
        }
        self.updateVisibility()
        self.updateIcons()
    }

    private func updateIcons() {
        // Avoid flicker: when an animation driver is active, store updates can call `updateIcons()` and
        // briefly overwrite the animated frame with the static (phase=nil) icon.
        let phase: Double? = self.needsMenuBarIconAnimation() ? self.animationPhase : nil
        if self.shouldMergeIcons {
            self.applyIcon(phase: phase)
            self.attachMenus()
        } else {
            UsageProvider.allCases.forEach { self.applyIcon(for: $0, phase: phase) }
            self.attachMenus(fallback: self.fallbackProvider)
        }
        self.updateAnimationState()
        self.updateBlinkingState()
    }

    /// Lazily retrieves or creates a status item for the given provider
    func lazyStatusItem(for provider: UsageProvider) -> NSStatusItem {
        if let existing = self.statusItems[provider] {
            return existing
        }
        let item = self.statusBar.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imageScaling = .scaleNone
        if let button = item.button {
            self.tagButton(button, provider: provider)
        }
        self.statusItems[provider] = item
        return item
    }

    private func updateVisibility() {
        let anyEnabled = !self.store.enabledProviders().isEmpty
        let force = self.store.debugForceAnimation
        let mergeIcons = self.shouldMergeIcons
        if mergeIcons {
            self.statusItem.isVisible = anyEnabled || force
            for item in self.statusItems.values {
                item.isVisible = false
            }
            self.attachMenus()
        } else {
            self.statusItem.isVisible = false
            let fallback = self.fallbackProvider
            for provider in UsageProvider.allCases {
                let isEnabled = self.isEnabled(provider)
                let shouldBeVisible = isEnabled || fallback == provider || force
                if shouldBeVisible {
                    let item = self.lazyStatusItem(for: provider)
                    item.isVisible = true
                } else if let item = self.statusItems[provider] {
                    item.isVisible = false
                }
            }
            self.attachMenus(fallback: fallback)
        }
        self.updateAnimationState()
        self.updateBlinkingState()
    }

    var fallbackProvider: UsageProvider? {
        self.store.enabledProviders().isEmpty ? .codex : nil
    }

    func isEnabled(_ provider: UsageProvider) -> Bool {
        self.store.isEnabled(provider)
    }

    private func refreshMenusForLoginStateChange() {
        if self.shouldMergeIcons {
            self.attachMenus()
        } else {
            self.attachMenus(fallback: self.fallbackProvider)
        }
    }

    private func attachMenus() {
        // Panel controller is created lazily on first click to avoid
        // evaluating SwiftUI views (with .glassEffect) before the window
        // system is fully ready — which can crash on cold first launch.
        self.statusItem.menu = nil
        if self.statusItem.button?.target !== self {
            self.statusItem.button?.target = self
            self.statusItem.button?.action = #selector(self.statusItemClicked(_:))
            self.statusItem.button?.sendAction(on: [.leftMouseUp])
        }
    }

    private func attachMenus(fallback: UsageProvider? = nil) {
        for provider in UsageProvider.allCases {
            let shouldHaveItem = self.isEnabled(provider) || fallback == provider
            if shouldHaveItem {
                let item = self.lazyStatusItem(for: provider)
                item.menu = nil
                if item.button?.target !== self {
                    item.button?.target = self
                    item.button?.action = #selector(self.statusItemClicked(_:))
                    item.button?.sendAction(on: [.leftMouseUp])
                }
            }
        }
    }

    private func rebuildProviderStatusItems() {
        for item in self.statusItems.values {
            self.statusBar.removeStatusItem(item)
        }
        self.statusItems.removeAll(keepingCapacity: true)

        for provider in self.settings.orderedProviders() {
            let item = self.statusBar.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.imageScaling = .scaleNone
            if let button = item.button {
                self.tagButton(button, provider: provider)
            }
            self.statusItems[provider] = item
        }
    }

    func isVisible(_ provider: UsageProvider) -> Bool {
        self.store.debugForceAnimation || self.isEnabled(provider) || self.fallbackProvider == provider
    }

    var shouldMergeIcons: Bool {
        self.settings.mergeIcons && self.store.enabledProviders().count > 1
    }

    func switchAccountSubtitle(for target: UsageProvider) -> String? {
        guard self.loginTask != nil, let provider = self.activeLoginProvider, provider == target else { return nil }
        let base: String
        switch self.loginPhase {
        case .idle: return nil
        case .requesting: base = "Requesting login…"
        case .waitingBrowser: base = "Waiting in browser…"
        }
        let prefix = ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
        return "\(prefix): \(base)"
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        // Determine which provider was clicked using the associated-object tag
        // (survives rebuildProviderStatusItems dictionary rebuilds).
        var clickedProvider: UsageProvider?
        if let button = sender as? NSStatusBarButton {
            clickedProvider = self.provider(for: button)
        }

        #if DEBUG
        let message = "[statusItemClicked] sender=\(type(of: sender as Any)), " +
            "clickedProvider=\(String(describing: clickedProvider)), " +
            "statusItems.keys=\(Array(self.statusItems.keys)), " +
            "shouldMerge=\(self.shouldMergeIcons)"
        print(message)
        #endif

        let previousProvider = self.lastMenuProvider
        if let clicked = clickedProvider {
            self.lastMenuProvider = clicked
        } else if !self.shouldMergeIcons {
            // Fallback: if the associated-object lookup failed, default to first enabled provider
            // so lastMenuProvider is never nil in split-icon mode.
            self.lastMenuProvider = self.store.enabledProviders().first
        }

        guard let button = (sender as? NSStatusBarButton) ?? self.statusItem.button else { return }
        self.ensurePanelController()

        // In split-icon mode, if the panel is already showing for a different
        // provider, dismiss immediately (no animation) and re-show for the new one.
        if let controller = self.panelController,
           controller.isShowing,
           clickedProvider != nil,
           clickedProvider != previousProvider
        {
            controller.dismiss(animated: false)
            controller.show(relativeTo: button)
        } else {
            self.panelController?.toggle(relativeTo: button)
        }
    }

    func ensurePanelController() {
        guard self.panelController == nil else { return }
        guard #available(macOS 26, *) else { return }
        self.panelController = MenuPanelController {
            self.makePanelContentView()
        }
    }

    @available(macOS 26, *)
    private func makePanelContentView() -> some View {
        MenuPanelContentView(
            store: self.store,
            settings: self.settings,
            account: self.account,
            updater: self.updater,
            cardWidth: 310,
            shouldMergeIcons: self.shouldMergeIcons,
            actions: self,
            cardModelProvider: { [weak self] provider in
                self?.menuCardModel(for: provider)
            },
            switcherIconProvider: { [weak self] provider in
                self?.switcherIcon(for: provider) ?? NSImage()
            },
            switcherWeeklyRemainingProvider: { [weak self] provider in
                self?.switcherWeeklyRemaining(for: provider)
            },
            includesOverviewProvider: { [weak self] providers in
                self?.includesOverviewTab(enabledProviders: providers) ?? false
            },
            resolvedSwitcherSelectionProvider: { [weak self] providers, includesOverview in
                self?.resolvedSwitcherSelection(
                    enabledProviders: providers,
                    includesOverview: includesOverview) ?? .provider(providers.first ?? .codex)
            },
            resolvedMenuProviderFn: { [weak self] in
                self?.resolvedMenuProvider()
            },
            tokenAccountDisplayProvider: { [weak self] provider in
                self?.tokenAccountMenuDisplayModel(for: provider)
            },
            openAIWebContextProvider: { [weak self] provider, showAll in
                self?.openAIWebContextModel(
                    currentProvider: provider,
                    showAllTokenAccounts: showAll) ?? OpenAIWebContextModel(
                    hasUsageBreakdown: false, hasCreditsHistory: false, hasCostHistory: false)
            })
            .environment(\.liquidGlassActive, LiquidGlassAvailability.shouldApplyGlass)
    }

    func dismissPanel() {
        self.panelController?.dismiss()
    }

    // MARK: - MenuPanelActions conformance

    func runSwitchAccount(provider: UsageProvider) {
        let item = NSMenuItem()
        item.representedObject = provider.rawValue
        self.runSwitchAccount(item)
    }

    func openTerminal(command: String) {
        let item = NSMenuItem()
        item.representedObject = command
        self.openTerminalCommand(item)
    }

    func openLoginToProvider(url: String) {
        let item = NSMenuItem()
        item.representedObject = url
        self.openLoginToProvider(item)
    }

    func copyError(_ message: String) {
        let item = NSMenuItem()
        item.representedObject = message
        self.copyError(item)
    }

    deinit {
        self.blinkTask?.cancel()
        self.loginTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}
