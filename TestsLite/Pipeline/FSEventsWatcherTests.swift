// TestsLite/Pipeline/FSEventsWatcherTests.swift
#if canImport(CoreServices)
import Testing
import Foundation
@testable import CodexBarCore

@Suite("FSEventsWatcher")
struct FSEventsWatcherTests {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "fsevents-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Tests

    /// Watch a temp dir, create a .jsonl file, verify the stream emits an event for it.
    @Test("detects file creation")
    func detectsFileCreation() async throws {
        let tmpDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let watcher = FSEventsWatcher()
        let stream = await watcher.watch(
            directories: [(url: tmpDir, fileExtensions: ["jsonl"])],
            coalescingLatency: 0.5
        )

        // Give FSEvents time to install the watch before we create the file.
        try await Task.sleep(for: .milliseconds(200))

        let targetFile = tmpDir.appending(path: "session.jsonl")
        try Data("{\"cost\":1.0}\n".utf8).write(to: targetFile)

        // Collect events for up to 5 seconds.
        let found = await withTaskTimeout(seconds: 5) { () -> Bool in
            for await batch in stream {
                let match = batch.contains { $0.path.hasSuffix("session.jsonl") }
                if match { return true }
            }
            return false
        }

        await watcher.stopAll()
        #expect(found == true, "Expected to receive an event for session.jsonl")
    }

    /// Watch for .jsonl only; create both .txt and .jsonl; verify only .jsonl events are emitted.
    @Test("filters extensions")
    func filtersExtensions() async throws {
        let tmpDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let watcher = FSEventsWatcher()
        let stream = await watcher.watch(
            directories: [(url: tmpDir, fileExtensions: ["jsonl"])],
            coalescingLatency: 0.5
        )

        try await Task.sleep(for: .milliseconds(200))

        let txtFile = tmpDir.appending(path: "notes.txt")
        let jsonlFile = tmpDir.appending(path: "data.jsonl")
        try Data("hello\n".utf8).write(to: txtFile)
        try Data("{}\n".utf8).write(to: jsonlFile)

        // Collect all events until we see a .jsonl event (or timeout).
        // Return a tuple of (sawTxt, sawJsonl) to avoid mutable captures in @Sendable closure.
        struct Result: Sendable { var sawTxt: Bool; var sawJsonl: Bool }

        let result: Result = await withTaskGroup(of: Result.self) { group in
            group.addTask {
                var r = Result(sawTxt: false, sawJsonl: false)
                for await batch in stream {
                    for event in batch {
                        if event.path.hasSuffix(".txt") { r.sawTxt = true }
                        if event.path.hasSuffix(".jsonl") { r.sawJsonl = true }
                    }
                    if r.sawJsonl { break }
                }
                return r
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return Result(sawTxt: false, sawJsonl: false)
            }
            let first = await group.next()!
            group.cancelAll()
            return first
        }

        await watcher.stopAll()
        #expect(result.sawTxt == false, "Should not have seen .txt events")
        #expect(result.sawJsonl == true, "Should have seen .jsonl events")
    }

    /// Watch a temp dir, call stopAll() immediately, verify the stream terminates.
    @Test("stopAll terminates the stream")
    func stopAllTerminates() async throws {
        let tmpDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let watcher = FSEventsWatcher()
        let stream = await watcher.watch(
            directories: [(url: tmpDir, fileExtensions: [])],
            coalescingLatency: 0.5
        )

        // Stop immediately — the stream should finish without yielding.
        await watcher.stopAll()

        // If the stream is properly finished, the for-await loop exits promptly.
        let terminated = await withTaskTimeout(seconds: 3) { () -> Bool in
            for await _ in stream {
                // If we get here, something was yielded unexpectedly.
            }
            return true   // loop exited = stream terminated
        }

        #expect(terminated == true, "Stream should terminate after stopAll()")
    }
}

// MARK: - Timeout helper

/// Runs `body` and returns its result, or returns `defaultValue` if the timeout elapses.
private func withTaskTimeout<T: Sendable>(
    seconds: Double,
    defaultValue: T? = nil,
    body: @Sendable @escaping () async -> T
) async -> T where T: ExpressibleByBooleanLiteral {
    await withTaskTimeout(seconds: seconds, default: false as! T, body: body)
}

private func withTaskTimeout<T: Sendable>(
    seconds: Double,
    `default` fallback: T,
    body: @Sendable @escaping () async -> T
) async -> T {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await body() }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        let first = await group.next()!
        group.cancelAll()
        return first ?? fallback
    }
}

// Overload for Void body (stopAll test)
private func withTaskTimeout(
    seconds: Double,
    body: @Sendable @escaping () async -> Void
) async {
    await withTaskGroup(of: Void?.self) { group in
        group.addTask { await body() }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
        }
        let _ = await group.next()
        group.cancelAll()
    }
}
#endif
