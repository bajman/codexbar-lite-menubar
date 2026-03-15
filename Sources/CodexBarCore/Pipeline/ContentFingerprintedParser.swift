// Sources/CodexBarCore/Pipeline/ContentFingerprintedParser.swift
import Foundation
import CryptoKit

enum ContentFingerprintedParser {

    enum Decision: Equatable, Sendable {
        case fullReparse
        case incremental(fromOffset: Int64)
        case skip
    }

    struct CacheEntry: Codable, Sendable, Equatable {
        var path: String
        var size: Int64
        var parsedOffset: Int64
        var headerFingerprint: Data    // SHA256 of first 4096 bytes
        var inodeIdentifier: UInt64    // stat().st_ino
    }

    private static let fingerprintSize = 4096

    static func buildCacheEntry(for fileURL: URL, parsedOffset: Int64) throws -> CacheEntry {
        let path = fileURL.path
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs[.size] as? Int64) ?? Int64((attrs[.size] as? UInt64) ?? 0)
        let inode = (attrs[.systemFileNumber] as? UInt64) ?? 0
        let fingerprintBytes = min(Int(size), fingerprintSize)
        let fingerprint = try computeFingerprint(for: fileURL, maxBytes: fingerprintBytes)
        return CacheEntry(
            path: path, size: size, parsedOffset: parsedOffset,
            headerFingerprint: fingerprint, inodeIdentifier: inode
        )
    }

    static func parseDecision(for fileURL: URL, cached: CacheEntry?) throws -> Decision {
        guard let cached else { return .fullReparse }
        let path = fileURL.path
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let currentSize = (attrs[.size] as? Int64) ?? Int64((attrs[.size] as? UInt64) ?? 0)
        let currentInode = (attrs[.systemFileNumber] as? UInt64) ?? 0

        if currentInode != cached.inodeIdentifier { return .fullReparse }
        if currentSize < cached.parsedOffset { return .fullReparse }
        if currentSize == cached.size && currentSize == cached.parsedOffset { return .skip }

        // Compare only the same byte range that was fingerprinted when the cache was built.
        // If cached.size < fingerprintSize the original hash covered fewer bytes; we must
        // hash the same prefix so an append doesn't look like a rotation.
        let compareBytes = min(Int(cached.size), fingerprintSize)
        let currentFingerprint = try computeFingerprint(for: fileURL, maxBytes: compareBytes)
        if currentFingerprint != cached.headerFingerprint { return .fullReparse }
        if currentSize > cached.parsedOffset { return .incremental(fromOffset: cached.parsedOffset) }
        return .skip
    }

    static func shouldEvictCacheEntry(for fileURL: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int64 ?? (attrs[.size] as? UInt64).map({ Int64($0) }) else {
            return true
        }
        return size <= 0
    }

    private static func computeFingerprint(for fileURL: URL, maxBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { handle.closeFile() }
        let headerData = handle.readData(ofLength: maxBytes)
        let digest = SHA256.hash(data: headerData)
        return Data(digest)
    }
}
