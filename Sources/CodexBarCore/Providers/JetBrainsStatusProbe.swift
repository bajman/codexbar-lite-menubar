import Foundation

public enum JetBrainsStatusProbeError: LocalizedError, Sendable, Equatable {
    case noQuotaInfo
    case parseFailed

    public var errorDescription: String? {
        switch self {
        case .noQuotaInfo:
            "No JetBrains quota information found."
        case .parseFailed:
            "Failed to parse JetBrains quota information."
        }
    }
}

public struct JetBrainsQuotaInfo: Sendable, Equatable {
    public let type: String
    public let used: Double
    public let maximum: Double
    public let available: Double?

    public init(type: String, used: Double, maximum: Double, available: Double?) {
        self.type = type
        self.used = used
        self.maximum = maximum
        self.available = available
    }
}

public struct JetBrainsRefillInfo: Sendable, Equatable {
    public let type: String
    public let amount: Double?

    public init(type: String, amount: Double?) {
        self.type = type
        self.amount = amount
    }
}

public struct JetBrainsStatusSnapshot: Sendable, Equatable {
    public let quotaInfo: JetBrainsQuotaInfo
    public let refillInfo: JetBrainsRefillInfo?

    public init(quotaInfo: JetBrainsQuotaInfo, refillInfo: JetBrainsRefillInfo?) {
        self.quotaInfo = quotaInfo
        self.refillInfo = refillInfo
    }
}

public enum JetBrainsStatusProbe {
    public static func parseXMLData(_ data: Data, detectedIDE _: String?) throws -> JetBrainsStatusSnapshot {
        guard var xml = String(data: data, encoding: .utf8) else {
            throw JetBrainsStatusProbeError.parseFailed
        }

        guard xml.contains("AIAssistantQuotaManager2") else {
            throw JetBrainsStatusProbeError.noQuotaInfo
        }

        let quotaValue = extractOptionValue(from: xml, optionName: "quotaInfo")
        guard let quotaValue, !quotaValue.isEmpty else {
            throw JetBrainsStatusProbeError.noQuotaInfo
        }

        let nextRefillValue = extractOptionValue(from: xml, optionName: "nextRefill")
        xml.removeAll(keepingCapacity: false)

        let quotaJSON = decodeEntities(quotaValue)
        guard
            let quotaData = quotaJSON.data(using: .utf8),
            let quotaObject = try JSONSerialization.jsonObject(with: quotaData) as? [String: Any]
        else {
            throw JetBrainsStatusProbeError.parseFailed
        }

        let quotaType = stringValue(quotaObject["type"]) ?? "unknown"
        let used = doubleValue(quotaObject["current"]) ?? 0
        let maximum = doubleValue(quotaObject["maximum"]) ?? 0
        let tariff = quotaObject["tariffQuota"] as? [String: Any]
        let available = doubleValue(tariff?["available"])
        let quota = JetBrainsQuotaInfo(type: quotaType, used: used, maximum: maximum, available: available)

        let refillInfo: JetBrainsRefillInfo?
        if let nextRefillValue, !nextRefillValue.isEmpty {
            let refillJSON = decodeEntities(nextRefillValue)
            if
                let refillData = refillJSON.data(using: .utf8),
                let refillObject = try? JSONSerialization.jsonObject(with: refillData) as? [String: Any]
            {
                let refillType = stringValue(refillObject["type"]) ?? "unknown"
                let tariff = refillObject["tariff"] as? [String: Any]
                let amount = doubleValue(tariff?["amount"])
                refillInfo = JetBrainsRefillInfo(type: refillType, amount: amount)
            } else {
                refillInfo = nil
            }
        } else {
            refillInfo = nil
        }

        return JetBrainsStatusSnapshot(quotaInfo: quota, refillInfo: refillInfo)
    }
}

extension JetBrainsStatusProbe {
    fileprivate static func extractOptionValue(from xml: String, optionName: String) -> String? {
        let patterns: [String] = [
            #"<option[^>]*name\s*=\s*["']\#(optionName)["'][^>]*value\s*=\s*["']([^"']*)["'][^>]*>"#,
            #"<option[^>]*value\s*=\s*["']([^"']*)["'][^>]*name\s*=\s*["']\#(optionName)["'][^>]*>"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
            guard let match = regex.firstMatch(in: xml, options: [], range: range), match.numberOfRanges > 1 else {
                continue
            }
            if let valueRange = Range(match.range(at: 1), in: xml) {
                return String(xml[valueRange])
            }
        }
        return nil
    }

    fileprivate static func decodeEntities(_ value: String) -> String {
        var decoded = value
        decoded = decoded.replacingOccurrences(of: "&#10;", with: "\n")
        decoded = decoded.replacingOccurrences(of: "&quot;", with: "\"")
        decoded = decoded.replacingOccurrences(of: "&apos;", with: "'")
        decoded = decoded.replacingOccurrences(of: "&amp;", with: "&")
        decoded = decoded.replacingOccurrences(of: "&lt;", with: "<")
        decoded = decoded.replacingOccurrences(of: "&gt;", with: ">")
        return decoded
    }

    fileprivate static func stringValue(_ any: Any?) -> String? {
        if let string = any as? String { return string }
        if let number = any as? NSNumber { return number.stringValue }
        return nil
    }

    fileprivate static func doubleValue(_ any: Any?) -> Double? {
        if let number = any as? NSNumber { return number.doubleValue }
        if let string = any as? String { return Double(string) }
        return nil
    }
}
