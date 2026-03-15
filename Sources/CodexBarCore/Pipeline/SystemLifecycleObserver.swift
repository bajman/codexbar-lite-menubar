#if canImport(AppKit)
import AppKit
import Foundation

/// Handles sleep/wake, App Nap prevention, and Space switch.
@MainActor
public final class SystemLifecycleObserver {
    private var activityToken: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []
    private var sleepTimestamp: Date?

    private let onWake: @Sendable (_ sleepDuration: TimeInterval) async -> Void
    private let onSleep: @Sendable () async -> Void
    private let onSpaceChange: @MainActor () -> Void

    public init(
        onWake: @escaping @Sendable (_ sleepDuration: TimeInterval) async -> Void,
        onSleep: @escaping @Sendable () async -> Void,
        onSpaceChange: @escaping @MainActor () -> Void
    ) {
        self.onWake = onWake
        self.onSleep = onSleep
        self.onSpaceChange = onSpaceChange
    }

    public func start() {
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
            let onSleep = self.onSleep
            Task { @MainActor in
                self.sleepTimestamp = Date()
                await onSleep()
            }
        })

        observers.append(ws.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let onWake = self.onWake
            Task { @MainActor in
                let duration = Date().timeIntervalSince(self.sleepTimestamp ?? Date())
                try? await Task.sleep(for: .seconds(duration > 3600 ? 5 : 3))
                await onWake(duration)
            }
        })

        observers.append(ws.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            let onSpaceChange = self?.onSpaceChange
            Task { @MainActor in onSpaceChange?() }
        })
    }

    public func stop() {
        let ws = NSWorkspace.shared.notificationCenter
        for observer in observers { ws.removeObserver(observer) }
        observers.removeAll()
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    nonisolated deinit {
        // Observers and activityToken are managed by stop().
        // nonisolated deinit cannot access @MainActor-isolated storage;
        // callers must call stop() before releasing this object.
    }
}
#endif
