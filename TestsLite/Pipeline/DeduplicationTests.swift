// TestsLite/Pipeline/DeduplicationTests.swift
import Foundation
import Testing
@testable import CodexBarCore

@Suite("Deduplication")
struct DeduplicationTests {

    // MARK: - Test 1: Claude Layer 1 — key-based dedup

    @Test("Claude Layer 1: duplicate messageId+requestId counted once")
    func claudeKeyBasedDedup() throws {
        let env = try DeduplicationTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2025, month: 12, day: 20)
        let iso0 = env.isoString(for: day)
        let iso1 = env.isoString(for: day.addingTimeInterval(1))

        let model = "claude-sonnet-4-20250514"
        let messageId = "msg_01DEDUP_TEST"
        let requestId = "req_01DEDUP_TEST"

        // Two identical entries with same messageId + requestId
        let entry1: [String: Any] = [
            "type": "assistant",
            "timestamp": iso0,
            "requestId": requestId,
            "message": [
                "id": messageId,
                "model": model,
                "usage": [
                    "input_tokens": 100,
                    "cache_creation_input_tokens": 10,
                    "cache_read_input_tokens": 20,
                    "output_tokens": 30,
                ],
            ],
        ]
        let entry2: [String: Any] = [
            "type": "assistant",
            "timestamp": iso1,
            "requestId": requestId,
            "message": [
                "id": messageId,
                "model": model,
                "usage": [
                    "input_tokens": 100,
                    "cache_creation_input_tokens": 10,
                    "cache_read_input_tokens": 20,
                    "output_tokens": 30,
                ],
            ],
        ]

        let fileURL = try env.writeClaudeProjectFile(
            relativePath: "project-a/session-dedup.jsonl",
            contents: env.jsonl([entry1, entry2]))

        let range = CostUsageScanner.CostUsageDayRange(since: day, until: day)
        let result = CostUsageScanner.parseClaudeFile(
            fileURL: fileURL,
            range: range,
            providerFilter: .all)

        let dayKey = CostUsageScanner.CostUsageDayRange.dayKey(from: day)
        let normModel = CostUsagePricing.normalizeClaudeModel(model)
        let packed = result.days[dayKey]?[normModel]
        #expect(packed != nil, "Expected day entry for \(dayKey)")

        // Should count once, not twice
        let input = packed?[0] ?? 0
        let cacheRead = packed?[1] ?? 0
        let cacheCreate = packed?[2] ?? 0
        let output = packed?[3] ?? 0
        #expect(input == 100, "Input should be 100, got \(input)")
        #expect(cacheRead == 20, "CacheRead should be 20, got \(cacheRead)")
        #expect(cacheCreate == 10, "CacheCreate should be 10, got \(cacheCreate)")
        #expect(output == 30, "Output should be 30, got \(output)")
    }

    // MARK: - Test 2: Claude Layer 2 — temporal grouping

    @Test("Claude Layer 2: missing requestId uses temporal grouping with MAX")
    func claudeTemporalGrouping() throws {
        let env = try DeduplicationTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2025, month: 12, day: 20)
        // Two entries within 5 seconds of each other
        let iso0 = env.isoString(for: day)
        let iso1 = env.isoString(for: day.addingTimeInterval(2))

        let model = "claude-sonnet-4-20250514"
        let messageId = "msg_01TEMPORAL_TEST"

        // Entry with messageId but NO requestId, output=30
        let entry1: [String: Any] = [
            "type": "assistant",
            "timestamp": iso0,
            "message": [
                "id": messageId,
                "model": model,
                "usage": [
                    "input_tokens": 100,
                    "cache_creation_input_tokens": 10,
                    "cache_read_input_tokens": 20,
                    "output_tokens": 30,
                ],
            ],
        ]
        // Same messageId, NO requestId, output=50, within 5s
        let entry2: [String: Any] = [
            "type": "assistant",
            "timestamp": iso1,
            "message": [
                "id": messageId,
                "model": model,
                "usage": [
                    "input_tokens": 100,
                    "cache_creation_input_tokens": 10,
                    "cache_read_input_tokens": 20,
                    "output_tokens": 50,
                ],
            ],
        ]

        let fileURL = try env.writeClaudeProjectFile(
            relativePath: "project-b/session-temporal.jsonl",
            contents: env.jsonl([entry1, entry2]))

        let range = CostUsageScanner.CostUsageDayRange(since: day, until: day)
        let result = CostUsageScanner.parseClaudeFile(
            fileURL: fileURL,
            range: range,
            providerFilter: .all)

        let dayKey = CostUsageScanner.CostUsageDayRange.dayKey(from: day)
        let normModel = CostUsagePricing.normalizeClaudeModel(model)
        let packed = result.days[dayKey]?[normModel]
        #expect(packed != nil, "Expected day entry for \(dayKey)")

        // Should use MAX (50), not SUM (80)
        let output = packed?[3] ?? 0
        #expect(output == 50, "Output should be MAX(30,50)=50, got \(output)")

        // Input and cache should also be MAX (both are 100, 20, 10 so MAX=same)
        let input = packed?[0] ?? 0
        let cacheRead = packed?[1] ?? 0
        let cacheCreate = packed?[2] ?? 0
        #expect(input == 100, "Input should be MAX(100,100)=100, got \(input)")
        #expect(cacheRead == 20, "CacheRead should be MAX(20,20)=20, got \(cacheRead)")
        #expect(cacheCreate == 10, "CacheCreate should be MAX(10,10)=10, got \(cacheCreate)")
    }

    // MARK: - Test 3: Codex counter-reset detection

    @Test("Codex counter-reset: tokens after reset are counted as absolute")
    func codexCounterReset() throws {
        let env = try DeduplicationTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2025, month: 12, day: 20)
        let iso0 = env.isoString(for: day)
        let iso1 = env.isoString(for: day.addingTimeInterval(1))
        let iso2 = env.isoString(for: day.addingTimeInterval(2))

        let model = "openai/gpt-5.2-codex"

        // First event: totals input=200, output=50
        let event1: [String: Any] = [
            "type": "event_msg",
            "timestamp": iso1,
            "payload": [
                "type": "token_count",
                "info": [
                    "total_token_usage": [
                        "input_tokens": 200,
                        "cached_input_tokens": 40,
                        "output_tokens": 50,
                    ],
                    "model": model,
                ],
            ],
        ]
        // Counter reset: totals drop to input=80, output=20
        // Without fix: max(0, 80-200) = 0, max(0, 20-50) = 0 -> lost
        // With fix: detected as reset, uses absolute values 80, 20
        let event2: [String: Any] = [
            "type": "event_msg",
            "timestamp": iso2,
            "payload": [
                "type": "token_count",
                "info": [
                    "total_token_usage": [
                        "input_tokens": 80,
                        "cached_input_tokens": 10,
                        "output_tokens": 20,
                    ],
                    "model": model,
                ],
            ],
        ]

        let fileURL = try env.writeCodexSessionFile(
            day: day,
            filename: "session-reset.jsonl",
            contents: env.jsonl([event1, event2]))

        let range = CostUsageScanner.CostUsageDayRange(since: day, until: day)
        let result = CostUsageScanner.parseCodexFile(
            fileURL: fileURL,
            range: range)

        let dayKey = CostUsageScanner.CostUsageDayRange.dayKey(from: day)
        let normModel = CostUsagePricing.normalizeCodexModel(model)
        let packed = result.days[dayKey]?[normModel]
        #expect(packed != nil, "Expected day entry for \(dayKey)")

        // First event: delta from 0 -> input=200, cached=40, output=50
        // Second event (reset): absolute -> input=80, cached=10, output=20
        // Total: input=280, cached=50, output=70
        let input = packed?[0] ?? 0
        let cached = packed?[1] ?? 0
        let output = packed?[2] ?? 0
        #expect(input == 280, "Input should be 200+80=280, got \(input)")
        #expect(cached == 50, "Cached should be 40+10=50, got \(cached)")
        #expect(output == 70, "Output should be 50+20=70, got \(output)")
    }
}

// MARK: - Test Environment

private struct DeduplicationTestEnvironment {
    let root: URL
    let cacheRoot: URL
    let codexSessionsRoot: URL
    let claudeProjectsRoot: URL

    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "codexbar-dedup-\(UUID().uuidString)",
            isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
        self.cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
        self.codexSessionsRoot = root.appendingPathComponent("codex-sessions", isDirectory: true)
        self.claudeProjectsRoot = root.appendingPathComponent("claude-projects", isDirectory: true)
        try FileManager.default.createDirectory(at: self.cacheRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: self.codexSessionsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: self.claudeProjectsRoot, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: self.root)
    }

    func makeLocalNoon(year: Int, month: Int, day: Int) throws -> Date {
        var comps = DateComponents()
        comps.calendar = Calendar.current
        comps.timeZone = TimeZone.current
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        guard let date = comps.date else { throw NSError(domain: "DeduplicationTestEnvironment", code: 1) }
        return date
    }

    func isoString(for date: Date) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.string(from: date)
    }

    func writeClaudeProjectFile(relativePath: String, contents: String) throws -> URL {
        let url = self.claudeProjectsRoot.appendingPathComponent(relativePath, isDirectory: false)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func writeCodexSessionFile(day: Date, filename: String, contents: String) throws -> URL {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: day)
        let y = String(format: "%04d", comps.year ?? 1970)
        let m = String(format: "%02d", comps.month ?? 1)
        let d = String(format: "%02d", comps.day ?? 1)

        let dir = self.codexSessionsRoot
            .appendingPathComponent(y, isDirectory: true)
            .appendingPathComponent(m, isDirectory: true)
            .appendingPathComponent(d, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = dir.appendingPathComponent(filename, isDirectory: false)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func jsonl(_ objects: [Any]) throws -> String {
        let lines = try objects.map { obj in
            let data = try JSONSerialization.data(withJSONObject: obj)
            guard let text = String(bytes: data, encoding: .utf8) else {
                throw NSError(domain: "DeduplicationTestEnvironment", code: 2)
            }
            return text
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
