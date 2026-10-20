import XCTest
@testable import OpenUsage

/// Regression: a model with only prefixed catalog keys was priced by whichever matching key was
/// longest — `grok-4` as `azure_ai/grok-4-fast-non-reasoning`, a different variant at 1/15 the price.
final class PricingCatalogFirstPartyTests: XCTestCase {
    private static func rates(_ input: Double, _ output: Double) -> ModelRates {
        ModelRates(inputPerMillion: input, outputPerMillion: output,
                   cacheWritePerMillion: input, cacheReadPerMillion: input / 10)
    }

    private let catalog = PricingCatalog(entries: [
        "xai/grok-4": rates(3, 15),
        "azure_ai/grok-4-fast-non-reasoning": rates(0.2, 0.5),
        "vercel_ai_gateway/xai/grok-4": rates(3, 15),
        "vercel_ai_gateway/xai/grok-3-mini-fast": rates(0.6, 4),
        "xai/grok-3-mini": rates(0.3, 0.5),
        "zai/glm-4.7": rates(0.6, 2.2),
        "cloudflare/@cf/zai-org/glm-4.7-flash": rates(0.06, 0.4),
        "claude-sonnet-4-20250514": rates(3, 15),
    ])

    func testFirstPartyKeyBeatsLongerVariantAndResellerKeys() {
        XCTAssertEqual(catalog.findFuzzy("grok-4")?.key, "xai/grok-4")
        XCTAssertEqual(catalog.findFuzzy("grok-3-mini")?.key, "xai/grok-3-mini")
    }

    func testFirstPartyMatchToleratesSeparatorVariants() {
        XCTAssertEqual(catalog.findFuzzy("glm-4.7")?.key, "zai/glm-4.7")
        XCTAssertEqual(catalog.findFuzzy("glm-4-7")?.key, "zai/glm-4.7")
    }

    func testWithoutFirstPartyKeyLongestMatchStillApplies() {
        XCTAssertEqual(catalog.findFuzzy("claude-sonnet-4")?.key, "claude-sonnet-4-20250514")
    }
}
