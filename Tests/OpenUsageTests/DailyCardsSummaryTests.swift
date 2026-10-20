import XCTest
@testable import OpenUsage

final class DailyCardsSummaryTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private lazy var now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 12))!

    private func history(_ days: [String: Int], models: [String: [ModelUsageEntry]] = [:]) -> ProviderUsageHistory {
        ProviderUsageHistory(
            series: DailyUsageSeries(daily: days.map { DailyUsageEntry(date: $0.key, totalTokens: $0.value, costUSD: nil) }),
            modelUsage: models.isEmpty ? nil
                : ModelUsageSeries(daily: models.map { DailyModelUsageEntry(date: $0.key, models: $0.value) })
        )
    }

    func testTokensSumProvidersAndRankThemForToday() throws {
        let summary = try XCTUnwrap(DailyCardsSummary.tokens(sources: [
            DailyCardSource(providerID: "codex", name: "Codex", history: history(["2026-10-18": 100, "2026-10-17": 50])),
            DailyCardSource(providerID: "claude", name: "Claude", history: history(["2026-10-18": 900, "2026-10-05": 7])),
            DailyCardSource(providerID: "cursor", name: "Cursor", history: nil),
        ], now: now, calendar: calendar))
        XCTAssertEqual(summary.total, 1000)
        XCTAssertEqual(summary.comparison, 50)
        XCTAssertEqual(summary.bars.count, DailyCardsSummary.barDays)
        XCTAssertEqual(summary.bars.first, 7, "The oldest bar is 13 days before today")
        XCTAssertEqual(summary.highlightedBar, DailyCardsSummary.barDays - 1)
        XCTAssertEqual(summary.providers.map(\.providerID), ["claude", "codex"])
    }

    func testTokensHiddenWithoutAnyHistoryAndEmptyBeforeFirstUse() throws {
        XCTAssertNil(DailyCardsSummary.tokens(sources: [DailyCardSource(providerID: "cursor", name: "Cursor", history: nil)],
                                              now: now, calendar: calendar))
        let quiet = try XCTUnwrap(DailyCardsSummary.tokens(
            sources: [DailyCardSource(providerID: "claude", name: "Claude", history: history(["2026-10-17": 5]))],
            now: now, calendar: calendar))
        XCTAssertEqual(quiet.total, 0)
        XCTAssertTrue(quiet.providers.isEmpty)
    }

    func testYesterdayAndThirtyDayPeriods() throws {
        let sources = [
            DailyCardSource(providerID: "claude", name: "Claude",
                            history: history(["2026-10-18": 900, "2026-10-17": 300, "2026-10-16": 100, "2026-09-18": 31])),
            DailyCardSource(providerID: "codex", name: "Codex", history: history(["2026-10-17": 600, "2026-09-17": 999])),
        ]
        let yesterday = try XCTUnwrap(DailyCardsSummary.tokens(sources: sources, period: .yesterday, now: now, calendar: calendar))
        XCTAssertEqual(yesterday.total, 900)
        XCTAssertEqual(yesterday.comparison, 100, "Yesterday compares with the day before")
        XCTAssertEqual(yesterday.highlightedBar, DailyCardsSummary.barDays - 2)
        XCTAssertEqual(yesterday.providers.map(\.providerID), ["codex", "claude"])

        let month = try XCTUnwrap(DailyCardsSummary.tokens(sources: sources, period: .thirtyDays, now: now, calendar: calendar))
        XCTAssertEqual(month.total, 900 + 300 + 100 + 31 + 600, "Sep 18 is the window's first day; Sep 17 is outside it")
        XCTAssertEqual(month.bars.count, 31)
        XCTAssertNil(month.highlightedBar)
        XCTAssertEqual(month.comparison, month.total / 31, accuracy: 0.0001)
    }

    func testModelsFollowThePeriod() throws {
        let summary = try XCTUnwrap(DailyCardsSummary.models(sources: [
            DailyCardSource(providerID: "claude", name: "Claude", history: history(["2026-10-17": 1], models: [
                "2026-10-18": [ModelUsageEntry(model: "today-model", totalTokens: 10, costUSD: 1)],
                "2026-10-17": [ModelUsageEntry(model: "yesterday-model", totalTokens: 10, costUSD: 5),
                               ModelUsageEntry(model: "today-model", totalTokens: 10, costUSD: 1)],
            ])),
        ], period: .yesterday, now: now, calendar: calendar))
        XCTAssertEqual(summary.models.map(\.model), ["yesterday-model", "today-model"])
        XCTAssertEqual(summary.models.last?.costUSD, 1)
    }

    func testSpendSumsPricedProvidersAndHidesWithoutPrices() throws {
        func priced(_ days: [String: Double?]) -> ProviderUsageHistory {
            ProviderUsageHistory(series: DailyUsageSeries(daily: days.map {
                DailyUsageEntry(date: $0.key, totalTokens: 1, costUSD: $0.value)
            }))
        }
        let summary = try XCTUnwrap(DailyCardsSummary.spend(sources: [
            DailyCardSource(providerID: "claude", name: "Claude", history: priced(["2026-10-18": 144.8, "2026-10-17": 80])),
            DailyCardSource(providerID: "codex", name: "Codex", history: priced(["2026-10-18": 1.6])),
            DailyCardSource(providerID: "antigravity", name: "Antigravity", history: priced(["2026-10-18": nil])),
        ], now: now, calendar: calendar))
        XCTAssertEqual(summary.total, 146.4, accuracy: 0.0001)
        XCTAssertEqual(summary.comparison, 80, accuracy: 0.0001)
        XCTAssertEqual(summary.providers.map(\.providerID), ["claude", "codex"])
        XCTAssertNil(DailyCardsSummary.spend(sources: [
            DailyCardSource(providerID: "antigravity", name: "Antigravity", history: priced(["2026-10-18": nil])),
        ], now: now, calendar: calendar))
    }

    func testSpendFlagsUnpricedUsageInsteadOfCountingZero() throws {
        let history = ProviderUsageHistory(series: DailyUsageSeries(daily: [
            DailyUsageEntry(date: "2026-10-17", totalTokens: 10, costUSD: 4),
            DailyUsageEntry(date: "2026-10-18", totalTokens: 10, costUSD: nil),
        ]))
        let today = try XCTUnwrap(DailyCardsSummary.spend(
            sources: [DailyCardSource(providerID: "claude", name: "Claude", history: history)], now: now, calendar: calendar))
        XCTAssertEqual(today.total, 0)
        XCTAssertTrue(today.hasUnpricedUsage)
        let yesterday = try XCTUnwrap(DailyCardsSummary.spend(
            sources: [DailyCardSource(providerID: "claude", name: "Claude", history: history)],
            period: .yesterday, now: now, calendar: calendar))
        XCTAssertFalse(yesterday.hasUnpricedUsage)
    }

    /// Regression: log scanners record a priced day total plus the models they couldn't price, so a
    /// partly priced day must still be flagged.
    func testSpendFlagsUnknownModelsOnAPricedDay() throws {
        let history = ProviderUsageHistory(
            series: DailyUsageSeries(daily: [DailyUsageEntry(date: "2026-10-18", totalTokens: 30, costUSD: 4)]),
            unknownModelsByDay: ["2026-10-18": ["mystery-model"]]
        )
        let sources = [DailyCardSource(providerID: "codex", name: "Codex", history: history)]
        let today = try XCTUnwrap(DailyCardsSummary.spend(sources: sources, now: now, calendar: calendar))
        XCTAssertEqual(today.total, 4)
        XCTAssertTrue(today.hasUnpricedUsage)
        let yesterday = try XCTUnwrap(DailyCardsSummary.spend(
            sources: sources, period: .yesterday, now: now, calendar: calendar))
        XCTAssertFalse(yesterday.hasUnpricedUsage)
    }

    func testSpendFlagsAProviderThatWasNeverPriced() throws {
        let priced = ProviderUsageHistory(series: DailyUsageSeries(daily: [
            DailyUsageEntry(date: "2026-10-18", totalTokens: 10, costUSD: 4),
        ]))
        let unpriced = ProviderUsageHistory(series: DailyUsageSeries(daily: [
            DailyUsageEntry(date: "2026-10-18", totalTokens: 50, costUSD: nil),
        ]))
        let summary = try XCTUnwrap(DailyCardsSummary.spend(sources: [
            DailyCardSource(providerID: "claude", name: "Claude", history: priced),
            DailyCardSource(providerID: "grok", name: "Grok", history: unpriced),
        ], now: now, calendar: calendar))
        XCTAssertEqual(summary.total, 4)
        XCTAssertTrue(summary.hasUnpricedUsage)
        XCTAssertEqual(summary.barRangeLast, "2026-10-18")
        XCTAssertEqual(summary.barRangeFirst, "2026-10-05")
    }

    func testModelsRankAcrossProvidersByCost() throws {
        let summary = try XCTUnwrap(DailyCardsSummary.models(sources: [
            DailyCardSource(providerID: "claude", name: "Claude", history: history(["2026-10-18": 1], models: ["2026-10-18": [
                ModelUsageEntry(model: "claude-opus", totalTokens: 10, costUSD: 6),
                ModelUsageEntry(model: "claude-haiku", totalTokens: 90, costUSD: 1),
            ]])),
            DailyCardSource(providerID: "codex", name: "Codex", history: history(["2026-10-18": 1], models: ["2026-10-18": [
                ModelUsageEntry(model: "gpt-5", totalTokens: 50, costUSD: 3),
            ], "2026-10-17": [ModelUsageEntry(model: "old", totalTokens: 999, costUSD: 99)]])),
        ], now: now, calendar: calendar))
        XCTAssertTrue(summary.rankedByCost)
        XCTAssertEqual(summary.models.map(\.model), ["claude-opus", "gpt-5", "claude-haiku"])
        XCTAssertEqual(summary.models.map(\.share).reduce(0, +), 1, accuracy: 0.0001)
        XCTAssertEqual(summary.models.first?.share ?? 0, 0.6, accuracy: 0.0001)
    }

    func testModelsFallBackToTokensAndCapAtFive() throws {
        let entries = (1...7).map { ModelUsageEntry(model: "m\($0)", totalTokens: $0 * 10, costUSD: nil) }
        let summary = try XCTUnwrap(DailyCardsSummary.models(sources: [
            DailyCardSource(providerID: "claude", name: "Claude", history: history(["2026-10-18": 1], models: ["2026-10-18": entries])),
        ], now: now, calendar: calendar))
        XCTAssertFalse(summary.rankedByCost)
        XCTAssertEqual(summary.models.count, DailyCardsSummary.modelLimit)
        XCTAssertEqual(summary.models.first?.model, "m7")
    }

    func testModelsHiddenWithoutModelHistoryAndEmptyWhenUnusedToday() throws {
        XCTAssertNil(DailyCardsSummary.models(sources: [
            DailyCardSource(providerID: "claude", name: "Claude", history: history(["2026-10-18": 5])),
        ], now: now, calendar: calendar))
        let quiet = try XCTUnwrap(DailyCardsSummary.models(sources: [
            DailyCardSource(providerID: "claude", name: "Claude", history: history(["2026-10-17": 5], models: [
                "2026-10-17": [ModelUsageEntry(model: "x", totalTokens: 5, costUSD: 1)],
            ])),
        ], now: now, calendar: calendar))
        XCTAssertTrue(quiet.models.isEmpty)
    }
}

final class ModelShortNameTests: XCTestCase {
    func testShortensFamilyVersionSlugs() {
        XCTAssertEqual(ModelShortName.make("claude-opus-5-5"), "Opus 5.5")
        XCTAssertEqual(ModelShortName.make("claude-sonnet-4-5-20250929"), "Sonnet 4.5")
        XCTAssertEqual(ModelShortName.make("claude-fable-5"), "Fable 5")
        XCTAssertEqual(ModelShortName.make("anthropic/claude-haiku-5-5"), "Haiku 5.5")
    }

    func testKeepsOtherSlugs() {
        XCTAssertEqual(ModelShortName.make("gpt-5.5-codex"), "gpt-5.5-codex")
        XCTAssertEqual(ModelShortName.make("Unattributed"), "Unattributed")
        XCTAssertEqual(ModelShortName.make("o4-mini"), "o4-mini")
    }
}

final class LiveCostEstimateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_324_800) // 2026-10-18 12:00 UTC
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func source(_ id: String, tokens: Int, cost: Double?) -> DailyCardSource {
        DailyCardSource(providerID: id, name: id, history: ProviderUsageHistory(series: DailyUsageSeries(daily: [
            DailyUsageEntry(date: "2026-10-18", totalTokens: tokens, costUSD: cost),
        ])))
    }

    func testPricesEachFamilyAtTodaysAverageAcrossAccounts() throws {
        // Claude: two accounts, $30 over 3M tokens = $10/MTok; 1M/min → $600/hr.
        // Codex: $2 over 1M = $2/MTok; 0.5M/min → $60/hr.
        let estimate = try XCTUnwrap(LiveCostEstimate.dollarsPerHour(
            rates: ["claude": 1_000_000, "codex": 500_000],
            sources: [source("claude", tokens: 2_000_000, cost: 20), source("claude@work", tokens: 1_000_000, cost: 10),
                      source("codex", tokens: 1_000_000, cost: 2)],
            now: now, calendar: utc))
        XCTAssertEqual(estimate, 660, accuracy: 0.001)
    }

    func testNilWithoutPricedUsageOrSpeed() {
        XCTAssertNil(LiveCostEstimate.dollarsPerHour(rates: ["claude": 1_000], sources: [source("claude", tokens: 10, cost: nil)],
                                                     now: now, calendar: utc))
        XCTAssertNil(LiveCostEstimate.dollarsPerHour(rates: ["claude": 0], sources: [source("claude", tokens: 10, cost: 1)],
                                                     now: now, calendar: utc))
    }
}
