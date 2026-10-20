import SwiftUI

/// The top-of-dashboard live card: the current speed, a 30-minute
/// stacked chart by provider or device. (Run-out warnings live on the provider meters.) The whole header row expands and
/// collapses it (see `LiveCardHeader`); the details open below it. Collapsed, it is one line with a
/// sparkline.
struct ActivityCard: View {
    let live: LiveActivityView
    /// The first speed reading hasn't arrived yet (a cold launch scanning the logs).
    var measuring = false
    /// Live speed priced at today's average cost per token (see `LiveCostEstimate`); shown when open.
    var dollarsPerHour: Double?

    @AppStorage(LiveActivitySettings.collapsedKey) private var collapsed = false
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @State private var breakdown = ActivityBreakdown.providers
    @Namespace private var chartSpace

    /// The Providers / Devices switch appears whenever there are remote devices to break down.
    private var showsBreakdownSwitch: Bool { live.showsDeviceBreakdown }
    private var activeBreakdown: ActivityBreakdown { showsBreakdownSwitch ? breakdown : .providers }
    private var series: [LiveSeries] { activeBreakdown == .providers ? live.providerSeries : live.deviceSeries }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LiveCardHeader(collapsed: $collapsed, name: "activity") { headlineRow }
            if !collapsed {
                // The header's small chart slides down and grows into this one (and back).
                StackedActivityChart(layers: layers)
                    .matchedGeometryEffect(id: LiveCardStyle.chartGeometryID, in: chartSpace)
                    .frame(height: 44)
                    .padding(.horizontal, LiveCardStyle.horizontalInset)
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
        .liveCardHideMenu("Activity Card", settingKey: LiveActivitySettings.cardKey)
        .animation(Motion.spring, value: collapsed)
    }

    private var headlineRow: some View {
        HStack(alignment: .center, spacing: 6) {
            LiveDot(active: (live.totalRate ?? 0) > 0)
            LiveCardFigure(value: headlineValue, unit: headerUnit, collapsed: collapsed, dimmed: speedState != .live)
            Spacer(minLength: 6)
            if collapsed {
                StackedActivityChart(layers: layers)
                    .matchedGeometryEffect(id: LiveCardStyle.chartGeometryID, in: chartSpace)
                    .frame(width: LiveCardStyle.collapsedChartWidth, height: LiveCardStyle.collapsedChartHeight)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Last 30 min")
                    .font(.system(size: density.planBadgePointSize))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if showsBreakdownSwitch {
                    QuietSegmentedControl(selection: $breakdown)
                }
            }
            ForEach(Array(series.enumerated()), id: \.element.id) { index, item in
                legendRow(item, color: ActivityPalette.color(for: item, index: index, breakdown: activeBreakdown))
            }
        }
    }

    private func legendRow(_ item: LiveSeries, color: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(item.name)
            if let note = item.note { Text(note).foregroundStyle(.tertiary).lineLimit(1) }
            Spacer(minLength: 4)
            Text(item.rate.map { "\(LiveFormat.rate($0))/min" } ?? "—")
                .monospacedDigit()
                .foregroundStyle(item.rate == nil ? .secondary : .primary)
        }
        .font(.system(size: density.supportingPointSize))
        .accessibilityElement(children: .combine)
    }

    private var layers: [(values: [Double], color: Color)] {
        series.enumerated().compactMap { index, item in
            item.history.map { ($0, ActivityPalette.color(for: item, index: index, breakdown: activeBreakdown)) }
        }
    }

    private enum SpeedState { case measuring, idle, live }

    /// Speed has three honest states: still reading the logs, nothing in use, or a live number.
    private var speedState: SpeedState {
        if let rate = live.totalRate, rate > 0 { return .live }
        return measuring ? .measuring : .idle
    }

    /// The unit beside the number, or — while speed is idle — when things last moved.
    /// Collapsed, the idle wording shortens ("12m ago") so it fits beside the chart; the live unit stays
    /// "tokens/min" in both states. Opened, a live speed adds its price per hour — an estimate at today's
    /// model mix, hence the ≈ — on the same baseline.
    private var headerUnit: String {
        let unit = unitText(compact: collapsed)
        guard !collapsed, speedState == .live, let dollarsPerHour else { return unit }
        return "\(unit) · ≈ \(Formatters.currency(dollarsPerHour, fractionDigits: dollarsPerHour < 10 ? 2 : 0))/hr"
    }

    private func unitText(compact: Bool) -> String {
        switch speedState {
        case .live: return "tokens/min"
        case .measuring: return compact ? "reading" : "reading logs"
        case .idle:
            guard let last = live.lastActiveAt else { return compact ? "no activity" : "no activity in 30 min" }
            let seconds = Date().timeIntervalSince(last)
            if seconds < 60 { return compact ? "just now" : "last active just now" }
            let ago = "\(Formatters.compactDuration(seconds) ?? "1m") ago"
            return compact ? ago : "last active \(ago)"
        }
    }

    private var headlineValue: String {
        switch speedState {
        case .live: return live.totalRate.map(LiveFormat.rate) ?? "—"
        case .measuring: return "—"
        case .idle: return "Idle"
        }
    }
}
