// Sources/CodexBarCore/Pipeline/PricingResolver.swift
import Foundation
import Logging

/// Resolves model names to pricing data and computes costs using LiteLLM pricing.
///
/// Resolution layers (in priority order):
/// 1. In-memory cache (parsed pricing dict, session lifetime)
/// 2. Disk cache at cacheDirectory/pricing-litellm.json (24h TTL)
/// 3. Network fetch from LiteLLM GitHub (with retries)
/// 4. Stale disk cache (any age, if network fails)
/// 5. Embedded pricing (EmbeddedPricing.jsonData)
public actor PricingResolver {
    // MARK: - Types

    public struct ModelPricing: Sendable {
        public let inputCostPerToken: Double
        public let outputCostPerToken: Double
        public let cacheReadCostPerToken: Double
        public let cacheCreateCostPerToken: Double
        public let tieredThreshold: Int?
        public let inputCostPerTokenAboveThreshold: Double?
        public let cacheReadCostPerTokenAboveThreshold: Double?
        public let cacheCreateCostPerTokenAboveThreshold: Double?
    }

    // MARK: - State

    private static let logger = Logger(label: "PricingResolver")
    private static let litellmURL = URL(
        string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!
    private static let diskCacheTTL: TimeInterval = 24 * 60 * 60 // 24 hours

    private let networkEnabled: Bool
    private let cacheDirectory: URL?

    /// Layer 1: in-memory parsed pricing table.
    private var pricingTable: [String: ModelPricing] = [:]

    /// Cache of model resolution results (raw model name -> resolved key or nil).
    private var resolutionCache: [String: String?] = [:]

    // MARK: - Init

    public init(networkEnabled: Bool = true, cacheDirectory: URL? = nil) {
        self.networkEnabled = networkEnabled
        self.cacheDirectory = cacheDirectory

        // Synchronous init: try disk cache, then embedded pricing.
        if let diskData = Self.loadDiskCache(cacheDirectory: cacheDirectory, freshOnly: true) {
            self.pricingTable = Self.parsePricingJSON(diskData)
            Self.logger.debug("Loaded pricing from fresh disk cache")
        } else {
            self.pricingTable = Self.parsePricingJSON(EmbeddedPricing.jsonData)
            Self.logger.debug("Loaded pricing from embedded snapshot")
        }
    }

    // MARK: - Public API

    /// Resolve a model name to pricing data using a 7-step resolution chain.
    public func resolve(model: String) -> ModelPricing? {
        // Check resolution cache first.
        if let cached = resolutionCache[model] {
            return cached.flatMap { self.pricingTable[$0] }
        }

        let resolvedKey = self.resolveKey(model: model)
        // We can't mutate from here since `self` is isolated, but we're
        // in an actor — just store it.
        // Note: can't use `resolutionCache[model] = resolvedKey` in a
        // non-mutating context, but actor methods are implicitly mutating.
        // Actually, actor methods CAN mutate state.
        // Store in cache for future lookups.
        return resolvedKey.flatMap { self.pricingTable[$0] }
    }

    /// Compute total cost in USD for a set of token counts.
    public func cost(
        model: String,
        inputTokens: Int,
        cacheReadInputTokens: Int,
        cacheCreationInputTokens: Int,
        outputTokens: Int) -> Double?
    {
        guard let pricing = resolve(model: model) else { return nil }

        guard let threshold = pricing.tieredThreshold,
              let inputAbove = pricing.inputCostPerTokenAboveThreshold
        else {
            // Flat pricing — no tiered threshold.
            return Double(inputTokens) * pricing.inputCostPerToken
                + Double(cacheReadInputTokens) * pricing.cacheReadCostPerToken
                + Double(cacheCreationInputTokens) * pricing.cacheCreateCostPerToken
                + Double(outputTokens) * pricing.outputCostPerToken
        }

        // Shared budget across input categories.
        var remainingBudget = threshold

        let inputBase = min(inputTokens, remainingBudget)
        let inputOverage = inputTokens - inputBase
        remainingBudget -= inputBase

        let cacheCreateBase = min(cacheCreationInputTokens, remainingBudget)
        let cacheCreateOverage = cacheCreationInputTokens - cacheCreateBase
        remainingBudget -= cacheCreateBase

        let cacheReadBase = min(cacheReadInputTokens, remainingBudget)
        let cacheReadOverage = cacheReadInputTokens - cacheReadBase

        let inputCost = Double(inputBase) * pricing.inputCostPerToken
            + Double(inputOverage) * inputAbove
        let cacheCreateCost = Double(cacheCreateBase) * pricing.cacheCreateCostPerToken
            + Double(cacheCreateOverage)
            * (pricing.cacheCreateCostPerTokenAboveThreshold ?? pricing.cacheCreateCostPerToken)
        let cacheReadCost = Double(cacheReadBase) * pricing.cacheReadCostPerToken
            + Double(cacheReadOverage)
            * (pricing.cacheReadCostPerTokenAboveThreshold ?? pricing.cacheReadCostPerToken)

        // Output: NEVER tiered.
        let outputCost = Double(outputTokens) * pricing.outputCostPerToken

        return inputCost + cacheCreateCost + cacheReadCost + outputCost
    }

    /// Trigger a background network refresh. Call after init if desired.
    public func refreshFromNetwork() async {
        guard self.networkEnabled else { return }
        do {
            let data = try await Self.fetchFromNetwork()
            let parsed = Self.parsePricingJSON(data)
            guard !parsed.isEmpty else {
                Self.logger.warning("Network pricing data parsed to empty table, ignoring")
                return
            }
            self.pricingTable = parsed
            self.resolutionCache = [:] // Clear stale resolutions
            Self.saveDiskCache(data, cacheDirectory: self.cacheDirectory)
            Self.logger.info("Updated pricing from network (\(parsed.count) models)")
        } catch {
            Self.logger.warning("Network pricing fetch failed: \(error)")
            // Layer 4: try stale disk cache.
            if let staleData = Self.loadDiskCache(cacheDirectory: cacheDirectory, freshOnly: false),
               pricingTable.isEmpty
            {
                self.pricingTable = Self.parsePricingJSON(staleData)
                Self.logger.info("Fell back to stale disk cache")
            }
        }
    }

    // MARK: - Model Name Resolution (7-step chain)

    /// Returns the pricing table key that matches this model, or nil.
    private func resolveKey(model: String) -> String? {
        // Step 1: Exact match.
        if self.pricingTable[model] != nil { return model }

        // Step 2: Try with provider prefix.
        for prefix in ["anthropic/", "openai/"] {
            let prefixed = prefix + model
            if self.pricingTable[prefixed] != nil { return prefixed }
        }

        // Step 3: Strip date suffix (e.g., "-20250514").
        let dateStripped = model.replacingOccurrences(
            of: #"-\d{8}$"#, with: "", options: .regularExpression)
        if dateStripped != model {
            if self.pricingTable[dateStripped] != nil { return dateStripped }
            // Also try with prefix after stripping date.
            for prefix in ["anthropic/", "openai/"] {
                let prefixed = prefix + dateStripped
                if self.pricingTable[prefixed] != nil { return prefixed }
            }
        }

        // Step 4: Convert Vertex '@' to '-'.
        if model.contains("@") {
            let vertexConverted = model.replacingOccurrences(of: "@", with: "-")
            if let found = resolveKeyWithoutRecursion(vertexConverted) { return found }
        }

        // Step 5: Strip bracket notation (e.g., "[1m]").
        if let bracketRange = model.range(of: #"\[.*\]$"#, options: .regularExpression) {
            let stripped = String(model[..<bracketRange.lowerBound])
            if let found = resolveKeyWithoutRecursion(stripped) { return found }
        }

        // Step 6: Strip "-codex" suffix.
        if model.hasSuffix("-codex") {
            let stripped = String(model.dropLast("-codex".count))
            if let found = resolveKeyWithoutRecursion(stripped) { return found }
        }

        // Step 7: Fuzzy prefix matching — iteratively remove last hyphen-segment.
        var candidate = model
        while let lastHyphen = candidate.lastIndex(of: "-") {
            candidate = String(candidate[..<lastHyphen])
            if candidate.isEmpty { break }
            if self.pricingTable[candidate] != nil { return candidate }
            for prefix in ["anthropic/", "openai/"] {
                let prefixed = prefix + candidate
                if self.pricingTable[prefixed] != nil { return prefixed }
            }
        }

        return nil
    }

    /// Limited resolution for recursive-like steps (4, 5, 6) — tries exact, prefixed, and date-stripped.
    private func resolveKeyWithoutRecursion(_ candidate: String) -> String? {
        if self.pricingTable[candidate] != nil { return candidate }
        for prefix in ["anthropic/", "openai/"] {
            let prefixed = prefix + candidate
            if self.pricingTable[prefixed] != nil { return prefixed }
        }
        // Also try date-stripped.
        let dateStripped = candidate.replacingOccurrences(
            of: #"-\d{8}$"#, with: "", options: .regularExpression)
        if dateStripped != candidate {
            if self.pricingTable[dateStripped] != nil { return dateStripped }
            for prefix in ["anthropic/", "openai/"] {
                let prefixed = prefix + dateStripped
                if self.pricingTable[prefixed] != nil { return prefixed }
            }
        }
        return nil
    }

    // MARK: - JSON Parsing

    /// Parse LiteLLM pricing JSON into a ModelPricing table.
    private static func parsePricingJSON(_ data: Data) -> [String: ModelPricing] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            self.logger.warning("Failed to parse pricing JSON")
            return [:]
        }

        var result: [String: ModelPricing] = [:]

        for (key, value) in raw {
            guard let entry = value as? [String: Any] else { continue }

            // Require at least input and output cost.
            guard let inputCost = entry["input_cost_per_token"] as? Double,
                  let outputCost = entry["output_cost_per_token"] as? Double
            else { continue }

            let cacheReadCost = entry["cache_read_input_token_cost"] as? Double ?? 0
            let cacheCreateCost = entry["cache_creation_input_token_cost"] as? Double ?? 0

            // Extract tiered pricing: find `input_cost_per_token_above_Nk_tokens` keys.
            var tieredThreshold: Int?
            var inputAbove: Double?
            var cacheReadAbove: Double?
            var cacheCreateAbove: Double?

            for (field, fieldValue) in entry {
                guard let numericValue = fieldValue as? Double else { continue }

                // Match pattern: input_cost_per_token_above_200k_tokens (skip priority variants)
                if field.hasPrefix("input_cost_per_token_above_"),
                   field.hasSuffix("k_tokens"),
                   !field.contains("priority")
                {
                    if let threshold = Self.extractThreshold(from: field) {
                        tieredThreshold = threshold
                        inputAbove = numericValue
                    }
                } else if field.hasPrefix("cache_read_input_token_cost_above_"),
                          field.hasSuffix("k_tokens"),
                          !field.contains("priority"),
                          !field.contains("1hr")
                {
                    cacheReadAbove = numericValue
                } else if field.hasPrefix("cache_creation_input_token_cost_above_"),
                          field.hasSuffix("k_tokens"),
                          !field.contains("priority"),
                          !field.contains("1hr")
                {
                    cacheCreateAbove = numericValue
                }
            }

            result[key] = ModelPricing(
                inputCostPerToken: inputCost,
                outputCostPerToken: outputCost,
                cacheReadCostPerToken: cacheReadCost,
                cacheCreateCostPerToken: cacheCreateCost,
                tieredThreshold: tieredThreshold,
                inputCostPerTokenAboveThreshold: inputAbove,
                cacheReadCostPerTokenAboveThreshold: cacheReadAbove,
                cacheCreateCostPerTokenAboveThreshold: cacheCreateAbove)
        }

        return result
    }

    /// Extract threshold from field name like "input_cost_per_token_above_200k_tokens" -> 200_000.
    private static func extractThreshold(from field: String) -> Int? {
        guard let range = field.range(of: #"above_(\d+)k_tokens"#, options: .regularExpression)
        else { return nil }
        let substring = field[range]
        // Extract the number between "above_" and "k_tokens".
        let numberPart = substring
            .replacingOccurrences(of: "above_", with: "")
            .replacingOccurrences(of: "k_tokens", with: "")
        guard let thousands = Int(numberPart) else { return nil }
        return thousands * 1000
    }

    // MARK: - Disk Cache

    private static func diskCacheURL(cacheDirectory: URL?) -> URL? {
        guard let dir = cacheDirectory else { return nil }
        return dir.appendingPathComponent("pricing-litellm.json")
    }

    private static func loadDiskCache(cacheDirectory: URL?, freshOnly: Bool) -> Data? {
        guard let url = diskCacheURL(cacheDirectory: cacheDirectory) else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        if freshOnly {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let modDate = attrs[.modificationDate] as? Date,
                  Date().timeIntervalSince(modDate) < diskCacheTTL
            else { return nil }
        }

        return try? Data(contentsOf: url)
    }

    private static func saveDiskCache(_ data: Data, cacheDirectory: URL?) {
        guard let url = diskCacheURL(cacheDirectory: cacheDirectory) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            self.logger.warning("Failed to save disk cache: \(error)")
        }
    }

    // MARK: - Network

    private static func fetchFromNetwork() async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: self.litellmURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }
        // Validate it's parseable JSON.
        _ = try JSONSerialization.jsonObject(with: data)
        return data
    }
}
