import AppKit
import CodexBarCore
import KeyboardShortcuts
import Observation
import QuartzCore
import SwiftUI

@main
struct CodexBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings: SettingsStore
    @State private var store: UsageStore
    private let preferencesSelection: PreferencesSelection
    private let account: AccountInfo

    init() {
        let env = ProcessInfo.processInfo.environment
        let storedLevel = CodexBarLog.parseLevel(UserDefaults.standard.string(forKey: "debugLogLevel")) ?? .verbose
        let level = CodexBarLog.parseLevel(env["CODEXBAR_LOG_LEVEL"]) ?? storedLevel
        CodexBarLog.bootstrapIfNeeded(.init(
            destination: .oslog(subsystem: "com.steipete.codexbar"),
            level: level,
            json: false))

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let gitCommit = Bundle.main.object(forInfoDictionaryKey: "CodexGitCommit") as? String ?? "unknown"
        let buildTimestamp = Bundle.main.object(forInfoDictionaryKey: "CodexBuildTimestamp") as? String ?? "unknown"
        CodexBarLog.logger(LogCategories.app).info(
            "CodexBar starting",
            metadata: [
                "version": version,
                "build": build,
                "git": gitCommit,
                "built": buildTimestamp,
            ])

        KeychainAccessGate.isDisabled = UserDefaults.standard.bool(forKey: "debugDisableKeychainAccess")
        KeychainPromptCoordinator.install()

        let preferencesSelection = PreferencesSelection()
        let settings = SettingsStore()
        let fetcher = UsageFetcher()
        let browserDetection = BrowserDetection(cacheTTL: BrowserDetection.defaultCacheTTL)
        let account = fetcher.loadAccountInfo()
        let store = UsageStore(fetcher: fetcher, browserDetection: browserDetection, settings: settings)
        self.preferencesSelection = preferencesSelection
        _settings = State(wrappedValue: settings)
        _store = State(wrappedValue: store)
        self.account = account
        CodexBarLog.setLogLevel(settings.debugLogLevel)
        self.appDelegate.configure(
            store: store,
            settings: settings,
            account: account,
            selection: preferencesSelection)
    }

    @SceneBuilder
    var body: some Scene {
        // Hidden 1×1 window to keep SwiftUI's lifecycle alive so `Settings` scene
        // shows the native toolbar tabs even though the UI is AppKit-based.
        WindowGroup("CodexBarLifecycleKeepalive") {
            HiddenWindowView()
        }
        .defaultSize(width: 20, height: 20)
        .windowStyle(.hiddenTitleBar)

        Settings {
            PreferencesView(
                settings: self.settings,
                store: self.store,
                updater: self.appDelegate.updaterController,
                selection: self.preferencesSelection)
        }
        .defaultSize(width: PreferencesTab.general.preferredWidth, height: PreferencesTab.general.preferredHeight)
        .windowResizability(.contentSize)
    }

    private func openSettings(tab: PreferencesTab) {
        self.preferencesSelection.tab = tab
        NSApp.activate(ignoringOtherApps: true)
        _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}

// MARK: - Updater abstraction

@MainActor
protocol UpdaterProviding: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var isAvailable: Bool { get }
    var unavailableReason: String? { get }
    var updateStatus: UpdateStatus { get }
    func checkForUpdates(_ sender: Any?)
}

/// No-op updater used for lite builds where in-app update checks are disabled.
final class DisabledUpdaterController: UpdaterProviding {
    var automaticallyChecksForUpdates: Bool = false
    var automaticallyDownloadsUpdates: Bool = false
    let isAvailable: Bool = false
    let unavailableReason: String?
    let updateStatus = UpdateStatus()

    init(unavailableReason: String? = nil) {
        self.unavailableReason = unavailableReason
    }

    func checkForUpdates(_ sender: Any?) {}
}

@MainActor
@Observable
final class UpdateStatus {
    static let disabled = UpdateStatus()
    var isUpdateReady: Bool

    init(isUpdateReady: Bool = false) {
        self.isUpdateReady = isUpdateReady
    }
}

@MainActor
private func makeUpdaterController() -> UpdaterProviding {
    DisabledUpdaterController()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController: UpdaterProviding = makeUpdaterController()
    private var statusController: StatusItemControlling?
    private var store: UsageStore?
    private var settings: SettingsStore?
    private var account: AccountInfo?
    private var preferencesSelection: PreferencesSelection?

    func configure(store: UsageStore, settings: SettingsStore, account: AccountInfo, selection: PreferencesSelection) {
        self.store = store
        self.settings = settings
        self.account = account
        self.preferencesSelection = selection
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        self.configureAppIconForMacOSVersion()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppNotifications.shared.requestAuthorizationOnStartup()
        self.ensureStatusController()
        KeyboardShortcuts.onKeyUp(for: .openMenu) { [weak self] in
            Task { @MainActor [weak self] in
                self?.statusController?.openMenuFromShortcut()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        TTYCommandRunner.terminateActiveProcessesForAppShutdown()
    }

    /// Use the classic (non-Liquid Glass) app icon on macOS versions before 26.
    private func configureAppIconForMacOSVersion() {
        if #unavailable(macOS 26) {
            self.applyClassicAppIcon()
        }
    }

    private func applyClassicAppIcon() {
        guard let classicIcon = Self.loadClassicIcon() else { return }
        NSApp.applicationIconImage = classicIcon
    }

    private static func loadClassicIcon() -> NSImage? {
        guard let url = self.classicIconURL(),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        return image
    }

    private static func classicIconURL() -> URL? {
        Bundle.main.url(forResource: "Icon-classic", withExtension: "icns")
    }

    private func ensureStatusController() {
        if self.statusController != nil { return }

        if let store, let settings, let account, let selection = self.preferencesSelection {
            self.statusController = StatusItemController.factory(
                store,
                settings,
                account,
                self.updaterController,
                selection)
            return
        }

        // Defensive fallback: this should not be hit in normal app lifecycle.
        CodexBarLog.logger(LogCategories.app)
            .error("StatusItemController fallback path used; settings/store mismatch likely.")
        assertionFailure("StatusItemController fallback path used; check app lifecycle wiring.")
        let fallbackSettings = SettingsStore()
        let fetcher = UsageFetcher()
        let browserDetection = BrowserDetection(cacheTTL: BrowserDetection.defaultCacheTTL)
        let fallbackAccount = fetcher.loadAccountInfo()
        let fallbackStore = UsageStore(fetcher: fetcher, browserDetection: browserDetection, settings: fallbackSettings)
        self.statusController = StatusItemController.factory(
            fallbackStore,
            fallbackSettings,
            fallbackAccount,
            self.updaterController,
            PreferencesSelection())
    }
}
