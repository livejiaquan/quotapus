import SwiftUI

// The Tokens and Models cards under the Activity card. Like it, each is one line when collapsed and the
// whole header row expands it. They read the rendered snapshots, so they follow Usage From and skip
// providers turned off in Customize.

extension AppContainer {
    /// Enabled providers' daily history in the current Usage From scope.
    var dailyCardSources: [DailyCardSource] {
        dataStore.snapshots
            .filter { enablement.isEnabled($0.key) }
            .map { DailyCardSource(providerID: $0.key, name: $0.value.displayName, history: $0.value.usageHistory) }
            .sorted { $0.providerID < $1.providerID }
    }
}

// Each slot owns its card's period (kept per card) because the summary is computed for it.

struct TokensCardSlot: View {
    let container: AppContainer
    let bottomSpacing: CGFloat
    @AppStorage(LiveActivitySettings.tokensPeriodKey) private var period = CardPeriod.today

    var body: some View {
        // Re-checked every minute so Today and Yesterday roll over at midnight while the panel is open.
        TimelineView(.everyMinute) { context in
            if let summary = DailyCardsSummary.tokens(sources: container.dailyCardSources, period: period, now: context.date) {
                DailyTotalsCard(kind: .tokens, summary: summary, period: $period).padding(.bottom, bottomSpacing)
            }
        }
    }
}

struct SpendCardSlot: View {
    let container: AppContainer
    let bottomSpacing: CGFloat
    @AppStorage(LiveActivitySettings.spendPeriodKey) private var period = CardPeriod.today

    var body: some View {
        // Re-checked every minute so Today and Yesterday roll over at midnight while the panel is open.
        TimelineView(.everyMinute) { context in
            if let summary = DailyCardsSummary.spend(sources: container.dailyCardSources, period: period, now: context.date) {
                DailyTotalsCard(kind: .spend, summary: summary, period: $period).padding(.bottom, bottomSpacing)
            }
        }
    }
}

struct ModelsCardSlot: View {
    let container: AppContainer
    let bottomSpacing: CGFloat
    @AppStorage(LiveActivitySettings.modelsPeriodKey) private var period = CardPeriod.today

    var body: some View {
        // Re-checked every minute so Today and Yesterday roll over at midnight while the panel is open.
        TimelineView(.everyMinute) { context in
            if let summary = DailyCardsSummary.models(sources: container.dailyCardSources, period: period, now: context.date) {
                ModelsCard(summary: summary, period: $period).padding(.bottom, bottomSpacing)
            }
        }
    }
}

extension CardPeriod {
    /// The word after a collapsed card's number: "today", "yesterday", "30 days".
    var shortLabel: String {
        switch self {
        case .today: "today"
        case .yesterday: "yesterday"
        case .thirtyDays: "30 days"
        }
    }
}

/// Tokens or Spend for the chosen period (Today / Yesterday / 30 Days) with daily bars; opened, the
/// period switch, a comparison figure, and each provider's share. Collapsed, it keeps the period.
struct DailyTotalsCard: View {
    enum Kind {
        case tokens, spend

        var name: String { self == .tokens ? "tokens" : "spend" }
        var collapsedKey: String {
            self == .tokens ? LiveActivitySettings.tokensCollapsedKey : LiveActivitySettings.spendCollapsedKey
        }

        func format(_ value: Double) -> String {
            self == .tokens ? LiveFormat.compact(value) : LiveFormat.dollars(value)
        }

        /// The period word alone when collapsed ("today", "30 days"), so it fits beside the bars.
        func unit(collapsed: Bool, period: CardPeriod) -> String {
            if collapsed { return period.shortLabel }
            // Spend is priced at API rates, an estimate rather than a bill, so it says so when open.
            let verb = self == .tokens ? "tokens" : "estimated"
            return period == .thirtyDays ? "\(verb) in 30 days" : "\(verb) \(period.shortLabel)"
        }

        func emptyText(_ period: CardPeriod) -> String {
            let what = self == .tokens ? "No tokens used" : "Nothing spent"
            switch period {
            case .today: return "\(what) yet today"
            case .yesterday: return "\(what) yesterday"
            case .thirtyDays: return "\(what) in the last 30 days"
            }
        }

        /// The figure beside the period switch.
        func comparison(_ summary: DailyTotalsSummary) -> String {
            let value = format(summary.comparison)
            switch summary.period {
            case .today: return "Yesterday \(value)"
            case .yesterday: return "Day before \(value)"
            case .thirtyDays: return "Daily avg \(value)"
            }
        }
    }

    let kind: Kind
    let summary: DailyTotalsSummary
    @Binding var period: CardPeriod

    @AppStorage private var collapsed: Bool
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @Namespace private var chartSpace

    init(kind: Kind, summary: DailyTotalsSummary, period: Binding<CardPeriod>) {
        self.kind = kind
        self.summary = summary
        _period = period
        _collapsed = AppStorage(wrappedValue: true, kind.collapsedKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LiveCardHeader(collapsed: $collapsed, name: kind.name) {
                LiveCardLeadingSlot()
                LiveCardFigure(value: kind.format(summary.total), unit: kind.unit(collapsed: collapsed, period: period),
                               collapsed: collapsed)
                Spacer(minLength: 6)
                if collapsed {
                    DailyBarsChart(layers: barLayers, highlighted: summary.highlightedBar)
                        .matchedGeometryEffect(id: LiveCardStyle.chartGeometryID, in: chartSpace)
                        .frame(width: LiveCardStyle.collapsedChartWidth, height: LiveCardStyle.collapsedChartHeight)
                }
            }
            if !collapsed {
                // Switching period swaps 14 bars for 31, which can't morph; crossfade instead of jumping.
                ZStack {
                    DailyBarsChart(layers: barLayers, highlighted: summary.highlightedBar)
                        .id(period)
                        .transition(.opacity)
                }
                .matchedGeometryEffect(id: LiveCardStyle.chartGeometryID, in: chartSpace)
                    .frame(height: 44)
                    .padding(.horizontal, LiveCardStyle.horizontalInset)
                // The bars cover more days than the selected period, so label their range.
                if let first = summary.barRangeFirst, let last = summary.barRangeLast {
                    HStack {
                        Text(Self.dayLabel(first))
                        Spacer(minLength: 4)
                        Text(Self.dayLabel(last))
                    }
                    .font(.system(size: density.planBadgePointSize - 1))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, LiveCardStyle.horizontalInset)
                    .padding(.top, 2)
                }
                details
                    .padding(.horizontal, LiveCardStyle.horizontalInset)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        // Clip so the header's hover fill follows the card's rounded corners.
        .clipShape(Theme.cardShape)
        .cardSurface()
        .liveCardHideMenu(kind == .tokens ? "Tokens Card" : "Spend Card",
                          settingKey: kind == .tokens ? LiveActivitySettings.tokensCardKey : LiveActivitySettings.spendCardKey)
        .animation(Motion.spring, value: collapsed)
        // The period lives in @AppStorage, whose writes don't carry the switch's animation transaction;
        // animating on the value itself is what makes the thumb slide and the bars crossfade, like the
        // Activity card's Providers / Devices switch.
        .animation(Motion.spring, value: period)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The period switch gets its own full-width row, so three labels never squeeze or wrap.
            QuietSegmentedControl(period: $period)
            Text(kind.comparison(summary))
                .font(.system(size: density.planBadgePointSize))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())
            if kind == .spend, summary.hasUnpricedUsage {
                Text(summary.providers.isEmpty ? "Usage in this period couldn't be priced"
                                               : "Some usage couldn't be priced and isn't counted")
                    .font(.system(size: density.supportingPointSize))
                    .foregroundStyle(Theme.notice)
            } else if summary.providers.isEmpty {
                Text(kind.emptyText(period))
                    .font(.system(size: density.supportingPointSize))
                    .foregroundStyle(.secondary)
            }
            ForEach(summary.providers, id: \.providerID) { provider in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(ProviderPalette.color(for: provider.providerID))
                        .frame(width: 8, height: 8)
                    Text(provider.name)
                    Spacer(minLength: 4)
                    Text(percent(provider.value, of: summary.total))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Text(kind.format(provider.value))
                        .frame(minWidth: 52, alignment: .trailing)
                        .contentTransition(.numericText())
                }
                .font(.system(size: density.supportingPointSize))
                .monospacedDigit()
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var barLayers: [(values: [Double], color: Color)] {
        summary.barLayers.map { ($0.values, ProviderPalette.color(for: $0.providerID)) }
    }

    private func percent(_ part: Double, of total: Double) -> String {
        guard total > 0 else { return "—" }
        let share = part / total * 100
        // A real but tiny share reads "<1%", not "0%".
        if share > 0, share < 0.5 { return "<1%" }
        return "\(Int(share.rounded()))%"
    }

    /// "2026-10-07" → "Oct 7".
    static func dayLabel(_ key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return key }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct ModelsCard: View {
    let summary: ModelsCardSummary
    @Binding var period: CardPeriod

    @AppStorage(LiveActivitySettings.modelsCollapsedKey) private var collapsed = true
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    private static let shadeOpacities: [Double] = [1, 0.7, 0.45, 0.3, 0.2]
    @Namespace private var chartSpace

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LiveCardHeader(collapsed: $collapsed, name: "models") { header }
            if !collapsed {
                if !summary.models.isEmpty {
                    shareBar
                        .matchedGeometryEffect(id: LiveCardStyle.chartGeometryID, in: chartSpace)
                        .frame(height: density.meterHeight)
                        .padding(.horizontal, LiveCardStyle.horizontalInset)
                        .padding(.top, 4)
                        .padding(.bottom, 4)
                }
                details
                    .padding(.horizontal, LiveCardStyle.horizontalInset)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        // Clip so the header's hover fill follows the card's rounded corners.
        .clipShape(Theme.cardShape)
        .cardSurface()
        .liveCardHideMenu("Models Card", settingKey: LiveActivitySettings.modelsCardKey)
        .animation(Motion.spring, value: collapsed)
        // The period lives in @AppStorage, whose writes don't carry the switch's animation transaction;
        // animating on the value itself is what makes the thumb slide and the bars crossfade, like the
        // Activity card's Providers / Devices switch.
        .animation(Motion.spring, value: period)
    }

    /// "62% Opus 5.5": the top model's share leads, like the other cards' numbers; the short name fits
    /// beside the bar, and the rows below keep the full slug.
    @ViewBuilder
    private var header: some View {
        LiveCardLeadingSlot()
        LiveCardFigure(value: summary.models.first.map { "\(Int(($0.share * 100).rounded()))%" } ?? "—",
                       unit: summary.models.first.map { ModelShortName.make($0.model) } ?? "no models",
                       collapsed: collapsed)
        // Today needs no mark; another period gets a quiet tag, since "44% Opus 5.5" can't say it.
        if period != .today {
            Text(period == .yesterday ? "· yday" : "· 30d")
                .font(.system(size: density.supportingPointSize))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()
        }
        Spacer(minLength: 6)
        if collapsed, !summary.models.isEmpty {
            shareBar
                .matchedGeometryEffect(id: LiveCardStyle.chartGeometryID, in: chartSpace)
                .frame(width: LiveCardStyle.collapsedChartWidth, height: density.meterHeight)
                .frame(height: LiveCardStyle.collapsedChartHeight)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            QuietSegmentedControl(period: $period)
            if !summary.models.isEmpty {
                Text(summary.rankedByCost ? "By cost" : "By tokens")
                    .font(.system(size: density.planBadgePointSize))
                    .foregroundStyle(.secondary)
            }
            if summary.models.isEmpty {
                Text(period == .today ? "No models used yet today"
                     : period == .yesterday ? "No models used yesterday" : "No models in the last 30 days")
                    .font(.system(size: density.supportingPointSize))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(summary.models.enumerated()), id: \.offset) { index, model in
                    row(model, color: color(at: index))
                }
            }
        }
    }

    private func row(_ model: ModelsCardSummary.Model, color: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(model.model).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Text("\(Int((model.share * 100).rounded()))%")
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
            // A model that couldn't be priced shows "—", not a misleading $0.
            Text(summary.rankedByCost ? model.costUSD.map { Formatters.currency($0) } ?? "—" : LiveFormat.tokens(model.tokens))
                .frame(minWidth: 56, alignment: .trailing)
        }
        .font(.system(size: density.supportingPointSize))
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }

    /// Each model takes its provider's color, lighter for each lower-ranked model of that provider.
    private func color(at index: Int) -> Color {
        let model = summary.models[index]
        let rank = summary.models[..<index].filter { $0.providerID == model.providerID }.count
        return ProviderPalette.color(for: model.providerID)
            .opacity(Self.shadeOpacities[min(rank, Self.shadeOpacities.count - 1)])
    }

    /// Segments at exact offsets with 2 pt gaps, filling the track when the shown shares add up to 100%.
    private var shareBar: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 2
            let count = summary.models.count
            let usable = max(0, proxy.size.width - gap * CGFloat(max(count - 1, 0)))
            let widths = summary.models.map { max(2, usable * $0.share) }
            ZStack(alignment: .leading) {
                Color.primary.opacity(0.1)
                ForEach(0..<count, id: \.self) { index in
                    Rectangle()
                        .fill(color(at: index))
                        .frame(width: widths[index])
                        .offset(x: widths[..<index].reduce(0, +) + gap * CGFloat(index))
                }
            }
            .clipShape(Capsule())
        }
        .accessibilityHidden(true)
    }
}
