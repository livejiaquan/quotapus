import SwiftUI

// Leaf views that read the live store themselves. Each 2-second live update re-renders only these, not
// the dashboard and every provider card around them (reading the store in the list's body made every
// update re-render the whole panel, which showed up as 100–300 ms stalls).

extension AppContainer {
    /// Live tokens per minute for one provider family in the current Usage From scope.
    func liveRate(_ family: LiveFamily) -> Double? {
        liveActivity.view(scope: dataStore.historyScopeID, enabledFamilies: liveEnabledFamilies).providerRates[family]
    }
}

/// The Activity card with its live inputs.
struct ActivityCardSlot: View {
    let container: AppContainer

    var body: some View {
        let live = container.liveActivity.view(scope: container.dataStore.historyScopeID,
                                               enabledFamilies: container.liveEnabledFamilies)
        ActivityCard(
            live: live,
            measuring: !container.liveActivity.hasMeasured,
            dollarsPerHour: LiveCostEstimate.dollarsPerHour(
                rates: Dictionary(uniqueKeysWithValues: live.providerRates.map { ($0.key.rawValue, $0.value) }),
                sources: container.dailyCardSources, now: Date())
        )
    }
}

/// "● 982K/min" on the provider header that owns its family's live chip.
struct LiveRateChipSlot: View {
    let family: LiveFamily
    let providerName: String
    @Environment(AppContainer.self) private var container: AppContainer?

    var body: some View {
        if let rate = container?.liveRate(family) {
            LiveRateChip(providerName: providerName, rate: rate)
        }
    }
}

/// The calm sweep over a live Session meter, paced by the family's current speed.
struct LiveSweepSlot: View {
    let family: LiveFamily
    @Environment(AppContainer.self) private var container: AppContainer?

    var body: some View {
        if let period = container?.liveRate(family).flatMap(CalmMeterSweep.period(forRate:)) {
            CalmMeterSweep(period: period)
        }
    }
}
