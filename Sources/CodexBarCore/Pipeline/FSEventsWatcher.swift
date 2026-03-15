// Sources/CodexBarCore/Pipeline/FSEventsWatcher.swift
#if canImport(CoreServices)
import CoreServices
import Foundation

// MARK: - File-scope C callback

/// C callback for FSEventStream. Runs on the FSEvents dispatch queue, not the actor executor.
/// Bridges to the actor via an unstructured Task to avoid reentrancy deadlock.
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

    // kFSEventStreamCreateFlagUseCFTypes: eventPaths is a CFArray of CFString
    let pathsArray = unsafeBitCast(eventPaths, to: CFArray.self)
    let count = CFArrayGetCount(pathsArray)

    var events: [FSEventsWatcher.RawEvent] = []
    events.reserveCapacity(count)

    for i in 0..<count {
        guard let rawPtr = CFArrayGetValueAtIndex(pathsArray, i) else { continue }
        let cfStr = unsafeBitCast(rawPtr, to: CFString.self)
        let path = cfStr as String
        let flags = eventFlags[i]
        let eventId = eventIds[i]
        events.append(FSEventsWatcher.RawEvent(path: path, flags: flags, eventId: eventId))
    }

    // Cross the actor boundary without blocking the C callback thread.
    Task { await watcher.handleEvents(events) }
}

// MARK: - FSEventsWatcher actor

/// Actor that wraps the macOS FSEvents C API to watch directory trees for file changes,
/// emitting filtered, coalesced events via AsyncStream.
actor FSEventsWatcher {

    // MARK: - Public types

    struct FileChangeEvent: Sendable {
        let path: String
        let flags: FSEventStreamEventFlags
        let eventId: FSEventStreamEventId
    }

    // MARK: - Internal raw event type (used by C callback bridge)

    struct RawEvent: Sendable {
        let path: String
        let flags: FSEventStreamEventFlags
        let eventId: FSEventStreamEventId
    }

    // MARK: - Private state

    private struct WatchEntry {
        let stream: FSEventStreamRef
        let fileExtensions: Set<String>   // empty = watch all extensions
        let continuation: AsyncStream<[FileChangeEvent]>.Continuation
        let coalescingLatency: TimeInterval
        /// Coalesced events waiting for the flush timer to fire
        var pendingEvents: [FileChangeEvent] = []
        /// Task that will fire after coalescingLatency and flush pending events
        var flushTask: Task<Void, Never>?
    }

    private var entries: [WatchEntry] = []
    private var lastCallbackTime: Date = .distantPast
    private let dispatchQueue = DispatchQueue(label: "com.codexbar.fsevents", qos: .utility)

    /// UserDefaults key prefix for persisting last event IDs
    private let lastEventIdKeyBase = "FSEventsWatcher.lastEventId"

    // MARK: - Public interface

    /// Watch a set of directories, emitting batched file-change events on the returned AsyncStream.
    /// - Parameters:
    ///   - directories: Array of `(url:, fileExtensions:)` tuples. Pass an empty `fileExtensions`
    ///     set to watch all extensions in that directory.
    ///   - coalescingLatency: How long to buffer rapid events before emitting them (default 2 s).
    func watch(
        directories: [(url: URL, fileExtensions: Set<String>)],
        coalescingLatency: TimeInterval = 2.0
    ) -> AsyncStream<[FileChangeEvent]> {
        let paths = directories.map { $0.url.path }

        // Merge all extensions from all watched directories for this stream's filter.
        let allExtensions = directories.reduce(into: Set<String>()) { $0.formUnion($1.fileExtensions) }

        // Retrieve persisted last event ID so FSEvents replays missed events.
        let storedIdKey = lastEventIdKeyFor(paths: paths)
        let sinceWhen: FSEventStreamEventId
        if let stored = UserDefaults.standard.object(forKey: storedIdKey) as? UInt64 {
            sinceWhen = stored
        } else {
            sinceWhen = FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
        }

        var continuation: AsyncStream<[FileChangeEvent]>.Continuation!
        let stream = AsyncStream<[FileChangeEvent]> { cont in
            continuation = cont
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: selfPtr,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags: FSEventStreamCreateFlags = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let fsStream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            paths as CFArray,
            sinceWhen,
            coalescingLatency,
            flags
        ) else {
            continuation.finish()
            return stream
        }

        FSEventStreamSetDispatchQueue(fsStream, dispatchQueue)
        FSEventStreamStart(fsStream)

        let entry = WatchEntry(
            stream: fsStream,
            fileExtensions: allExtensions,
            continuation: continuation,
            coalescingLatency: coalescingLatency
        )
        entries.append(entry)
        return stream
    }

    /// Stop all active FSEvent streams and finish all AsyncStreams.
    func stopAll() {
        for entry in entries {
            entry.flushTask?.cancel()
            FSEventStreamStop(entry.stream)
            FSEventStreamInvalidate(entry.stream)
            FSEventStreamRelease(entry.stream)
            entry.continuation.finish()
        }
        entries.removeAll()
    }

    /// Returns the time elapsed since the last FSEvents callback fired (useful for health checks).
    func lastCallbackAge() -> TimeInterval {
        Date().timeIntervalSince(lastCallbackTime)
    }

    // MARK: - Internal: called from the C callback via Task

    /// Process raw events coming off the FSEvents dispatch queue.
    func handleEvents(_ rawEvents: [RawEvent]) {
        lastCallbackTime = Date()

        for i in 0..<entries.count {
            var addedAny = false

            for raw in rawEvents {
                let mustScan = (raw.flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs)) != 0

                let pass: Bool
                if mustScan {
                    pass = true
                } else if entries[i].fileExtensions.isEmpty {
                    pass = true
                } else {
                    let ext = (raw.path as NSString).pathExtension
                    pass = entries[i].fileExtensions.contains(ext)
                }

                guard pass else { continue }

                let event = FileChangeEvent(path: raw.path, flags: raw.flags, eventId: raw.eventId)
                entries[i].pendingEvents.append(event)
                addedAny = true

                // Persist the latest event ID.
                UserDefaults.standard.set(raw.eventId, forKey: lastEventIdKeyBase)
            }

            // Arm the flush timer if we added new events and there isn't one running already.
            if addedAny && entries[i].flushTask == nil {
                let latency = entries[i].coalescingLatency
                let idx = i
                entries[i].flushTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(latency))
                    await self?.flush(index: idx)
                }
            }
        }
    }

    // MARK: - Private helpers

    /// Emit all pending events for the entry at `index` and reset its flush state.
    func flush(index: Int) {
        guard index < entries.count else { return }
        guard !entries[index].pendingEvents.isEmpty else {
            entries[index].flushTask = nil
            return
        }
        let batch = entries[index].pendingEvents
        entries[index].pendingEvents = []
        entries[index].flushTask = nil
        entries[index].continuation.yield(batch)
    }

    private func lastEventIdKeyFor(paths: [String]) -> String {
        let sorted = paths.sorted().joined(separator: ":")
        return "\(lastEventIdKeyBase).\(sorted.hashValue)"
    }
}
#endif
