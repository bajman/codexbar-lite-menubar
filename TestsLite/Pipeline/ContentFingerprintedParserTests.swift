// TestsLite/Pipeline/ContentFingerprintedParserTests.swift
import Testing
import Foundation
@testable import CodexBarCore

@Suite("ContentFingerprintedParser")
struct ContentFingerprintedParserTests {

    @Test("returns fullReparse for new file with no cache entry")
    func newFileFullReparse() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "fp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let file = tmpDir.appending(path: "test.jsonl")
        try Data("line1\nline2\n".utf8).write(to: file)
        let decision = try ContentFingerprintedParser.parseDecision(for: file, cached: nil)
        #expect(decision == .fullReparse)
    }

    @Test("returns skip for unchanged file")
    func unchangedFileSkip() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "fp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let file = tmpDir.appending(path: "test.jsonl")
        let content = Data("line1\nline2\n".utf8)
        try content.write(to: file)
        let entry = try ContentFingerprintedParser.buildCacheEntry(for: file, parsedOffset: Int64(content.count))
        let decision = try ContentFingerprintedParser.parseDecision(for: file, cached: entry)
        #expect(decision == .skip)
    }

    @Test("returns incremental for appended file")
    func appendedFileIncremental() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "fp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let file = tmpDir.appending(path: "test.jsonl")
        let initial = Data("line1\n".utf8)
        try initial.write(to: file)
        let entry = try ContentFingerprintedParser.buildCacheEntry(for: file, parsedOffset: Int64(initial.count))
        let handle = try FileHandle(forWritingTo: file)
        handle.seekToEndOfFile()
        handle.write(Data("line2\n".utf8))
        handle.closeFile()
        let decision = try ContentFingerprintedParser.parseDecision(for: file, cached: entry)
        if case .incremental(let offset) = decision {
            #expect(offset == Int64(initial.count))
        } else {
            Issue.record("Expected .incremental, got \(decision)")
        }
    }

    @Test("returns fullReparse for truncated file")
    func truncatedFileFullReparse() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "fp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let file = tmpDir.appending(path: "test.jsonl")
        let content = Data("line1\nline2\nline3\n".utf8)
        try content.write(to: file)
        let entry = try ContentFingerprintedParser.buildCacheEntry(for: file, parsedOffset: Int64(content.count))
        try Data("short\n".utf8).write(to: file)
        let decision = try ContentFingerprintedParser.parseDecision(for: file, cached: entry)
        #expect(decision == .fullReparse)
    }

    @Test("returns fullReparse when header content changes (rotation)")
    func rotatedFileFullReparse() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "fp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let file = tmpDir.appending(path: "test.jsonl")
        try Data("original-content-line1\n".utf8).write(to: file)
        let entry = try ContentFingerprintedParser.buildCacheEntry(for: file, parsedOffset: 22)
        try Data("replaced-content-XXX1\nmore-data-here\n".utf8).write(to: file)
        let decision = try ContentFingerprintedParser.parseDecision(for: file, cached: entry)
        #expect(decision == .fullReparse)
    }
}
