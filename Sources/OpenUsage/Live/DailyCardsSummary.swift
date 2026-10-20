import Foundation

/// One provider's history as the Tokens and Models cards read it. Snapshots are already scoped by
/// Usage From, so these cards follow that switch like the spend rows do.
struct DailyCardSource: Equatable {
    var providerID: String
    var name: String
    var history: ProviderUsageHistory?
}

/// The period a Tokens, Spend, or Models card shows; each card keeps its own. "30 Days" matches the
/// spend rows' Last 30 Days: today plus the previous 30 calendar days.
enum CardPeriod: String, CaseIterable, Sendable {
    case today, yesterday, thirtyDays

    var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thirtyDays: "30 Days"
        }
    }
}

/// The Tokens and Spend cards: the selected period's total across enabled providers, the bars, a
/// comparison figure, and each provider's share of the period.
struct DailyTotalsSummary: Equatable {
    struct Provider: Equatable {
        var providerID: String
        var name: String
        var value: Double
    }

    var period: CardPeriod
    var total: Double
    /// Today: yesterday's total. Yesterday: the day before. 30 Days: the daily average.
    var comparison: Double
    /// Daily totals, oldest first: the last 14 days, or the whole 30-day window.
    var bars: [Double]
    /// The bar drawn at full strength (the selected day); nil for 30 Days, where every day counts.
    var highlightedBar: Int?
    /// Each provider's share of every bar, aligned with `bars`, largest provider first (drawn at the
    /// bottom of the stack).
    var barLayers: [BarLayer] = []
    /// The first and last bar's day keys (yyyy-MM-dd), for the date labels under the bars.
    var barRangeFirst: String? = nil
    var barRangeLast: String? = nil

    struct BarLayer: Equatable {
        var providerID: String
        var values: [Double]
    }
    /// Providers with something in the period, most first.
    var providers: [Provider]
    /// Spend only: a priced provider also has usage in the period it couldn't price (an unknown model),
    /// so the total leaves some usage out rather than counting it as $0.
    var hasUnpricedUsage = false
}

/// The Models card: today's models across every enabled provider, ranked like Top Models Today (by
/// cost, or by tokens when nothing was priced).
struct ModelsCardSummary: Equatable {
    struct Model: Equatable {
        var model: String
        var providerID: String
        var tokens: Int
        var costUSD: Double?
        /// Share of today's cost (or tokens when ranked by tokens), 0...1.
        var share: Double
    }

    var models: [Model]
    var rankedByCost: Bool
}

enum DailyCardsSummary {
    static let barDays = 14
    static let modelLimit = 5

    static var windowDays: Int { UsageHistoryWindow.previousDays + 1 }

    /// Nil when no enabled provider keeps a daily history, which hides the card.
    static func tokens(sources: [DailyCardSource], period: CardPeriod = .today, now: Date,
                       calendar: Calendar = .current) -> DailyTotalsSummary? {
        totals(sources: sources.filter { $0.history != nil }, period: period, now: now, calendar: calendar) { entry in
            entry.map { Double($0.totalTokens) } ?? 0
        }
    }

    /// Nil when no enabled provider priced any usage in the 30-day window, which hides the card.
    static func spend(sources: [DailyCardSource], period: CardPeriod = .today, now: Date,
                      calendar: Calendar = .current) -> DailyTotalsSummary? {
        let keys = Set(dayKeys(count: windowDays, through: now, calendar: calendar))
        let priced = sources.filter { source in
            source.history?.series.daily.contains { keys.contains($0.date) && $0.costUSD != nil } ?? false
        }
        let periodKeys = Set(periodKeys(period, now: now, calendar: calendar))
        var summary = totals(sources: priced, period: period, now: now, calendar: calendar) { $0?.costUSD ?? 0 }
        // Any enabled provider with usage it couldn't price, including one never priced at all, makes the
        // total incomplete; say so instead of quietly leaving it out.
        // Log scanners price every day they count and list the models they couldn't price separately
        // (`unknownModelsByDay`), so a day can read $4 while also holding unpriced usage.
        summary?.hasUnpricedUsage = sources.contains { source in
            guard let history = source.history else { return false }
            return history.series.daily.contains {
                periodKeys.contains($0.date) && $0.totalTokens > 0 && $0.costUSD == nil
            } || history.unknownModelsByDay.contains { periodKeys.contains($0.key) && !$0.value.isEmpty }
        }
        return summary
    }

    /// The day keys a period covers, oldest first.
    static func periodKeys(_ period: CardPeriod, now: Date, calendar: Calendar = .current) -> [String] {
        let window = dayKeys(count: windowDays, through: now, calendar: calendar)
        switch period {
        case .today: return [window[window.count - 1]]
        case .yesterday: return [window[window.count - 2]]
        case .thirtyDays: return window
        }
    }

    private static func totals(
        sources: [DailyCardSource], period: CardPeriod, now: Date, calendar: Calendar,
        value: (DailyUsageEntry?) -> Double
    ) -> DailyTotalsSummary? {
        guard !sources.isEmpty else { return nil }
        func amount(_ source: DailyCardSource, _ key: String) -> Double {
            value(source.history?.series.daily.first { $0.date == key })
        }
        func daily(_ key: String) -> Double { sources.reduce(0) { $0 + amount($1, key) } }
        let window = dayKeys(count: windowDays, through: now, calendar: calendar)
        let keys = periodKeys(period, now: now, calendar: calendar)
        let total = keys.reduce(0) { $0 + daily($1) }
        let barKeys: [String], highlighted: Int?, comparison: Double
        switch period {
        case .today, .yesterday:
            barKeys = Array(window.suffix(barDays))
            highlighted = period == .today ? barDays - 1 : barDays - 2
            comparison = daily(window[window.count - (period == .today ? 2 : 3)])
        case .thirtyDays:
            barKeys = window
            highlighted = nil
            comparison = total / Double(window.count)
        }
        let bars = barKeys.map(daily)

        var barLayers: [DailyTotalsSummary.BarLayer] = []
        for source in sources {
            let values: [Double] = barKeys.map { amount(source, $0) }
            if values.contains(where: { $0 > 0 }) {
                barLayers.append(DailyTotalsSummary.BarLayer(providerID: source.providerID, values: values))
            }
        }
        barLayers.sort { lhs, rhs in lhs.values.reduce(0, +) > rhs.values.reduce(0, +) }
        let providers = sources
            .map { source in
                DailyTotalsSummary.Provider(providerID: source.providerID, name: source.name,
                                            value: keys.reduce(0) { $0 + amount(source, $1) })
            }
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
        return DailyTotalsSummary(period: period, total: total, comparison: comparison, bars: bars,
                                  highlightedBar: highlighted, barLayers: barLayers, barRangeFirst: barKeys.first, barRangeLast: barKeys.last,
                                  providers: providers)
    }

    /// Nil when no enabled provider keeps per-model history; an empty list means nothing used yet today.
    static func models(sources: [DailyCardSource], period: CardPeriod = .today, now: Date,
                       calendar: Calendar = .current) -> ModelsCardSummary? {
        let withModels = sources.filter { $0.history?.modelUsage != nil }
        guard !withModels.isEmpty else { return nil }
        let keys = Set(periodKeys(period, now: now, calendar: calendar))
        var merged: [String: ModelsCardSummary.Model] = [:]
        var order: [String] = []
        for source in withModels {
            let days = source.history?.modelUsage?.daily.filter { keys.contains($0.date) } ?? []
            for entry in days.flatMap(\.models) where entry.totalTokens > 0 || (entry.costUSD ?? 0) > 0 {
                let key = source.providerID + "\u{1F}" + entry.model
                if var existing = merged[key] {
                    existing.tokens += entry.totalTokens
                    existing.costUSD = sum(existing.costUSD, entry.costUSD)
                    merged[key] = existing
                } else {
                    merged[key] = .init(model: entry.model, providerID: source.providerID,
                                        tokens: entry.totalTokens, costUSD: entry.costUSD, share: 0)
                    order.append(key)
                }
            }
        }
        let models = order.compactMap { merged[$0] }
        let totalCost = models.compactMap(\.costUSD).reduce(0, +)
        let byCost = totalCost > 0
        let total = byCost ? totalCost : Double(models.map(\.tokens).reduce(0, +))
        guard total > 0 else { return ModelsCardSummary(models: [], rankedByCost: false) }
        let ranked = models.map { model -> ModelsCardSummary.Model in
            var model = model
            model.share = (byCost ? (model.costUSD ?? 0) : Double(model.tokens)) / total
            return model
        }
        .sorted { $0.share > $1.share }
        return ModelsCardSummary(models: Array(ranked.prefix(modelLimit)), rankedByCost: byCost)
    }

    private static func sum(_ lhs: Double?, _ rhs: Double?) -> Double? {
        guard lhs != nil || rhs != nil else { return nil }
        return (lhs ?? 0) + (rhs ?? 0)
    }

    /// Day keys oldest first, ending with today.
    static func dayKeys(count: Int, through now: Date, calendar: Calendar = .current) -> [String] {
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
                .map { DailyUsageAccumulator.dayKey(from: $0, calendar: calendar) }
        }
    }
}

/// A short, readable model name for a card header, where space is tight: "claude-opus-5-5" →
/// "Opus 5.5", "claude-sonnet-4-5-20250929" → "Sonnet 4.5". Names that don't follow the
/// family-major-minor shape keep their slug, minus a vendor prefix and a trailing date.
enum ModelShortName {
    static func make(_ slug: String) -> String {
        var name = slug.trimmingCharacters(in: .whitespaces)
        if let slash = name.lastIndex(of: "/") { name = String(name[name.index(after: slash)...]) }
        if name.lowercased().hasPrefix("claude-") { name = String(name.dropFirst("claude-".count)) }
        if let range = name.range(of: #"-\d{8}$"#, options: .regularExpression) { name.removeSubrange(range) }
        let parts = name.split(separator: "-").map(String.init)
        guard parts.count >= 2, parts.count <= 3, let family = parts.first, family.allSatisfy(\.isLetter),
              parts.dropFirst().allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
        else { return name }
        return family.prefix(1).uppercased() + family.dropFirst() + " " + parts.dropFirst().joined(separator: ".")
    }
}

/// The Activity card's "≈ $84/hr": live speed priced at today's average cost per token for each
/// provider family (all of its accounts together). An estimate — the price follows today's model mix —
/// and nil while nothing active has priced usage today.
enum LiveCostEstimate {
    static func dollarsPerHour(
        rates: [String: Double],
        sources: [DailyCardSource],
        now: Date,
        calendar: Calendar = .current,
        family: (String) -> String = ProviderAccountID.family(of:)
    ) -> Double? {
        let today = DailyUsageAccumulator.dayKey(from: now, calendar: calendar)
        var total = 0.0
        var priced = false
        for (familyID, rate) in rates where rate > 0 {
            let days = sources.filter { family($0.providerID) == familyID }
                .compactMap { $0.history?.series.daily.first { $0.date == today } }
            let tokens = days.map(\.totalTokens).reduce(0, +)
            let cost = days.compactMap(\.costUSD).reduce(0, +)
            guard tokens > 0, cost > 0 else { continue }
            total += rate * 60 * cost / Double(tokens)
            priced = true
        }
        return priced ? total : nil
    }
}
