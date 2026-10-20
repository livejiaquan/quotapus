import XCTest
@testable import OpenUsage

/// Checks the bundled `pricing_supplement.json` itself, which Quotapus ships instead of fetching a copy.
final class BundledSupplementTests: XCTestCase {
    private func bundledSupplement() throws -> PricingSupplement {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/OpenUsage/Resources/pricing_supplement.json")
        return try PricingSupplement.decode(from: Data(contentsOf: url))
    }

    func testHaiku55HasItsLongContextTier() throws {
        let rates = try XCTUnwrap(try bundledSupplement().pricing["claude-haiku-5-5"])
        XCTAssertEqual(rates.inputPerMillion, 0.1, accuracy: 1e-9)
        XCTAssertEqual(rates.outputPerMillion, 0.5, accuracy: 1e-9)
        XCTAssertEqual(rates.cacheReadPerMillion, 0.01, accuracy: 1e-9)
        XCTAssertEqual(rates.longContextThresholdTokens, 100_000)
        XCTAssertEqual(rates.inputAbove200kPerMillion ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(rates.outputAbove200kPerMillion ?? 0, 2.5, accuracy: 1e-9)
    }

    func testHaiku55LogSlugsResolve() throws {
        let supplement = try bundledSupplement()
        for slug in ["claude-haiku-5-5", "claude-haiku-5.5", "claude-haiku-5-5-thinking"] {
            let range = NSRange(slug.startIndex..., in: slug)
            XCTAssertTrue(supplement.aliasRules.contains {
                $0.canonical == "claude-haiku-5-5" && $0.pattern.firstMatch(in: slug, range: range) != nil
            }, slug)
        }
    }
}
