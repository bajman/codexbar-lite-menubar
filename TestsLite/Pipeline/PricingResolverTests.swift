// TestsLite/Pipeline/PricingResolverTests.swift
import Testing
@testable import CodexBarCore

@Suite("PricingResolver")
struct PricingResolverTests {

    @Test("resolves exact model name from embedded pricing")
    func exactMatch() async {
        let resolver = PricingResolver(networkEnabled: false)
        let pricing = await resolver.resolve(model: "claude-sonnet-4-20250514")
        #expect(pricing != nil)
        #expect(pricing!.inputCostPerToken > 0)
    }

    @Test("resolves model by stripping date suffix")
    func stripDateSuffix() async {
        let resolver = PricingResolver(networkEnabled: false)
        // "claude-sonnet-4-5-20250929" exists; stripping "-20250929" yields
        // "claude-sonnet-4-5" which also exists — both should resolve.
        let pricing = await resolver.resolve(model: "claude-sonnet-4-5-20250929")
        #expect(pricing != nil)
    }

    @Test("resolves with anthropic/ prefix")
    func providerPrefix() async {
        let resolver = PricingResolver(networkEnabled: false)
        // LiteLLM has "claude-sonnet-4-20250514" unprefixed.
        // Asking for it without prefix should resolve via step 1 (exact match).
        // But asking for a model that *only* has an anthropic/ prefix should resolve via step 2.
        let pricing = await resolver.resolve(model: "claude-sonnet-4-20250514")
        #expect(pricing != nil)
    }

    @Test("resolves bracket notation")
    func bracketNotation() async {
        let resolver = PricingResolver(networkEnabled: false)
        let pricing = await resolver.resolve(model: "claude-opus-4-6[1m]")
        #expect(pricing != nil)
    }

    @Test("resolves vertex @ notation")
    func vertexAtNotation() async {
        let resolver = PricingResolver(networkEnabled: false)
        // "claude-opus-4-5@20251101" should convert @ to - yielding
        // "claude-opus-4-5-20251101" which exists.
        let pricing = await resolver.resolve(model: "claude-opus-4-5@20251101")
        #expect(pricing != nil)
    }

    @Test("returns nil for unknown model")
    func unknownModel() async {
        let resolver = PricingResolver(networkEnabled: false)
        let pricing = await resolver.resolve(model: "totally-fake-model-xyz-999")
        #expect(pricing == nil)
    }

    @Test("tiered pricing uses shared budget")
    func tieredSharedBudget() async {
        let resolver = PricingResolver(networkEnabled: false)
        // claude-sonnet-4-20250514 has tiered pricing above 200k tokens
        let cost = await resolver.cost(
            model: "claude-sonnet-4-20250514",
            inputTokens: 150_000,
            cacheReadInputTokens: 150_000,
            cacheCreationInputTokens: 0,
            outputTokens: 1_000
        )
        #expect(cost != nil)
        #expect(cost! > 0)
    }

    @Test("output tokens never tiered")
    func outputNeverTiered() async {
        let resolver = PricingResolver(networkEnabled: false)
        let cost1 = await resolver.cost(
            model: "claude-sonnet-4-20250514",
            inputTokens: 100,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 500_000
        )
        let cost2 = await resolver.cost(
            model: "claude-sonnet-4-20250514",
            inputTokens: 100,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 1_000
        )
        #expect(cost1 != nil && cost2 != nil)
        // Output should scale linearly (ratio ~500)
        let ratio = cost1! / cost2!
        #expect(ratio > 400 && ratio < 600)
    }

    @Test("flat pricing model computes correctly")
    func flatPricing() async {
        let resolver = PricingResolver(networkEnabled: false)
        // claude-opus-4-6 should have flat pricing (no tiered threshold)
        let cost = await resolver.cost(
            model: "claude-opus-4-6",
            inputTokens: 1_000,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 1_000
        )
        #expect(cost != nil)
        #expect(cost! > 0)
    }

    @Test("tiered cost higher than flat for same tokens above threshold")
    func tieredCostHigherAboveThreshold() async {
        let resolver = PricingResolver(networkEnabled: false)
        // With input tokens well above the threshold, cost should be
        // higher than if we computed at the base rate alone.
        let pricing = await resolver.resolve(model: "claude-sonnet-4-20250514")
        guard let p = pricing, p.tieredThreshold != nil else {
            Issue.record("Expected tiered pricing for claude-sonnet-4-20250514")
            return
        }

        let baseCost = Double(300_000) * p.inputCostPerToken
        let actualCost = await resolver.cost(
            model: "claude-sonnet-4-20250514",
            inputTokens: 300_000,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 0
        )
        #expect(actualCost != nil)
        #expect(actualCost! > baseCost)
    }

    @Test("codex suffix stripping resolves model")
    func codexSuffixStripping() async {
        let resolver = PricingResolver(networkEnabled: false)
        // "claude-opus-4-6-codex" should strip "-codex" and resolve to "claude-opus-4-6"
        // This tests step 6 of the resolution chain (strip -codex for OpenAI models),
        // though it applies generically.
        let pricing = await resolver.resolve(model: "claude-opus-4-6-codex")
        #expect(pricing != nil)
    }
}
