import SwiftUI

/// The dashboard display: one inset group per provider (System Settings style). A provider's icon + name
/// sits above a rounded container holding its metric rows, so heterogeneous metric sets read as belonging
/// to their provider. Rows are the shared `WidgetRowView`, fed by the same `WidgetDataStore` the menu bar
/// uses.
///
/// Reordering works here directly (no Customize needed): drag any metric row to reorder it within its
/// provider, or drag a provider's header line to reorder whole providers. Customize stays the discoverable,
/// obvious place to do the same plus toggle metrics on/off. Both surfaces use the same local gesture/geometry
/// helper so they work inside the menu-bar popover without a system drag/drop session.
struct WidgetGroupedListView: View {
    @Environment(AppContainer.self) private var container
    @Environment(LayoutStore.self) private var layout
    @Environment(WidgetDataStore.self) private var dataStore
    let reorderSpaceName: String
    @Binding var reorderLift: ReorderLift?

    @State private var frameStore = ReorderFrameStore()
    @State private var activeProviderID: String?
    @State private var activeMetricID: String?
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @AppStorage(LiveActivitySettings.headerSpeedKey) private var headerSpeedEnabled = true
    @AppStorage(LiveActivitySettings.animatedMetersKey) private var animatedMetersEnabled = true

    @Environment(\.resetClaims) private var resetClaims

    var body: some View {
        // Provider-section spacing is noticeably wider than the in-card row rhythm (so groups
        // still read as groups); the exact step comes from the density setting.
        VStack(alignment: .leading, spacing: density.sectionSpacing) {
            ForEach(layout.displayGroups) { group in
                section(group)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onPreferenceChange(ReorderFramePreferenceKey.self) { frameStore.frames = $0 }
        .animation(Motion.spring, value: layout.displayGroups.map(\.provider.id))
    }

    /// Runs of two or more adjacent Today / Yesterday / Last 30 Days rows (never across the caret or a
    /// links row) render as one Usage row: `heads` maps a run's first metric to its columns, and the
    /// run's later metrics are `members`, which render nothing.
    private typealias UsageStatRuns = (heads: [String: [ResolvedRow]], members: Set<String>)

    private static func usageStatRuns(_ rows: [DashboardMetricCardRow]) -> UsageStatRuns {
        var dataByID: [String: ResolvedRow] = [:]
        let ids = rows.map { row -> String in
            guard case .metric(let entry) = row else { return "separator.\(row.id)" }
            dataByID[entry.descriptor.id] = entry
            return entry.descriptor.id
        }
        var heads: [String: [ResolvedRow]] = [:]
        var members: Set<String> = []
        for case .usageStats(let run) in UsageStatGrouping.group(ids) {
            heads[run[0]] = run.compactMap { dataByID[$0] }
            members.formUnion(run.dropFirst())
        }
        return (heads, members)
    }

    private static func accent(for providerID: String) -> Color? {
        switch LiveFamily(rawValue: ProviderAccountID.family(of: providerID)) {
        case .claude: ActivityPalette.claude
        case .codex: ActivityPalette.codex
        case nil: nil
        }
    }

    /// The live family this provider card shows, when it is the card that owns that family's chip.
    /// Only the family is decided here; the speed itself is read by small leaf views
    /// (`LiveSlots.swift`), so the list's body never depends on the 2-second live updates.
    private func liveFamily(for providerID: String) -> LiveFamily? {
        LiveActivityComposer.chipFamily(
            forProviderID: providerID, providerIDs: layout.displayGroups.map(\.provider.id),
            ownerIDs: container.liveOwnerCardIDs
        )
    }

    private func section(_ group: ProviderGroup) -> some View {
        // A provider with nothing to show yet (every Always Visible row "No data") is just its header with a
        // quiet tag; the card comes back on its own once data arrives. Rows hidden behind the chevron don't
        // count, or a hidden chart with data would keep a card of "No data" rows open.
        let hasData = group.alwaysShownWidgets.contains { widget in
            layout.descriptor(for: widget).map { dataStore.data(for: $0).hasData } ?? false
        }
        return VStack(alignment: .leading, spacing: density.headerToCardSpacing) {
            header(group, noData: !hasData)
            if hasData {
                container(group)
            }
        }
        .opacity(activeProviderID == group.provider.id ? 0 : 1)
        .reorderFrame(id: group.provider.id, in: .named(reorderSpaceName))
    }

    private func header(_ group: ProviderGroup, noData: Bool) -> some View {
        ProviderSectionHeader(
            provider: group.provider,
            plan: dataStore.plan(for: group.provider.id),
            warning: dataStore.headerNotice(for: group.provider.id),
            refreshing: dataStore.refreshingProviderIDs.contains(group.provider.id),
            staleness: dataStore.stalenessHint(for: group.provider.id),
            liveFamily: headerSpeedEnabled ? liveFamily(for: group.provider.id) : nil,
            noData: noData
        )
        // The header sits just inside the card edge (4 pt), a step left of the card content (12 pt).
        .padding(.horizontal, 4)
        .highPriorityGesture(providerDragGesture(for: group))
        .contextMenu {
            // Hides the whole provider section (the Customize provider list brings it back). Mirrors
            // the per-metric "Hide" but one level up, so the verb order reads the same on a header as a row.
            Button("Hide \(group.provider.displayName)") {
                container.enablement.setEnabled(false, for: group.provider.id)
            }
            Divider()
            Button("Refresh \(group.provider.displayName)") {
                Task { await dataStore.refreshOnUserRequest(providerID: group.provider.id) }
            }
            Button("Customize…") {
                openCustomize(for: group.provider.id)
            }
        }
    }

    /// A row's placed widget paired with its resolved descriptor + data, so each `dataStore.data(for:)`
    /// is computed once per render and reused by both the condensing rule and the row. Keyed off the
    /// `PlacedWidget` so `ForEach` identity stays exactly what it was before this was precomputed.
    private struct ResolvedRow: Identifiable {
        let widget: PlacedWidget
        let descriptor: WidgetDescriptor
        let data: WidgetData
        var id: PlacedWidget.ID { widget.id }
    }

    private enum DashboardMetricCardRow: Identifiable {
        case metric(ResolvedRow)
        case divider
        /// #596: the provider's quick-link buttons (Status / Console / Dashboard ...), pinned at the
        /// bottom of the collapsible expanded section. They collapse with the caret — part of the
        /// expander, not always-visible chrome.
        case links([ProviderLink])

        var id: String {
            switch self {
            case .metric(let row):
                "metric:\(row.descriptor.id)"
            case .divider:
                "expanded-divider"
            case .links:
                "provider-links"
            }
        }
    }

    private func container(_ group: ProviderGroup) -> some View {
        // Resolve each row's descriptor + data exactly once per render, then reuse it for both the
        // neighbor-aware condensing rule and the row itself — `dataStore.data(for:)` used to be
        // recomputed several times per row (twice per adjacent pair plus once in `row`).
        let providerID = group.provider.id
        let isExpanded = layout.isProviderExpanded(providerID)
        let alwaysRows = resolvedRows(group.alwaysShownWidgets)
        let expandedRows = resolvedRows(group.expandedWidgets)
        // The caret separates Always Visible and On Demand rows, so text-row condensing should not
        // bridge across it. Each side tightens only against rows on the same side of the separator.
        let condensedIDs = visibleCondensedTextRowIDs(alwaysRows: alwaysRows, expandedRows: isExpanded ? expandedRows : [])
        let cardRows = metricCardRows(
            alwaysRows: alwaysRows,
            expandedRows: expandedRows,
            hasExpandedMetrics: group.hasExpandedMetrics,
            isExpanded: isExpanded,
            // Quotapus's design has no Status / Dashboard buttons in the card; the dashboard stays data only.
            links: []
        )
        let usageRuns = Self.usageStatRuns(cardRows)
        let separatedGroups = separatedGroupIDs(cardRows, usageRuns: usageRuns)
        // Same card builder the lifted preview uses, so the floating chip can't drift from the live card.
        return DashboardMetricCard {
            // One stable list keeps the drag-owning metric row alive when it crosses the caret boundary.
            // Separate always-shown/expanded loops can tear that source view down before `onEnded` fires,
            // leaving the lift overlay visible until another drag forces a reset.
            ForEach(cardRows) { cardRow in
                switch cardRow {
                case .metric(let entry):
                    if isHidden(entry, usageRuns: usageRuns) {
                        EmptyView()
                    } else if let columns = usageRuns.heads[entry.descriptor.id] {
                        // Each column gets its own menu, so Hide on Yesterday hides Yesterday, not Today.
                        UsageStatRow(columns: columns.map(\.data),
                                     separatedAbove: separatedGroups.contains(entry.descriptor.id)) { index in
                            AnyView(rowMenu(columns[index].descriptor, providerID: providerID))
                        }
                    } else {
                        row(entry.descriptor, data: entry.data, in: providerID,
                            condensedTop: condensedIDs.contains(entry.descriptor.id),
                            separatedAbove: separatedGroups.contains(entry.descriptor.id))
                    }
                case .links(let links):
                    ProviderLinksView(links: links)
                case .divider:
                    OnDemandToggle(isExpanded: isExpanded) {
                        AppLog.info(.statusItem, "ui: \(isExpanded ? "collapse" : "expand") \(providerID)")
                        withAnimation(Motion.spring) {
                            _ = layout.setProviderExpanded(!isExpanded, for: providerID)
                        }
                    }
                    .reorderFrame(id: expandedDividerID(for: providerID), in: .named(reorderSpaceName))
                }
            }
        }
    }

    private func resolvedRows(_ widgets: [PlacedWidget]) -> [ResolvedRow] {
        widgets.compactMap { widget -> ResolvedRow? in
            guard let descriptor = layout.descriptor(for: widget) else { return nil }
            return ResolvedRow(widget: widget, descriptor: descriptor, data: dataStore.data(for: descriptor))
        }
    }

    private func metricCardRows(
        alwaysRows: [ResolvedRow],
        expandedRows: [ResolvedRow],
        hasExpandedMetrics: Bool,
        isExpanded: Bool,
        links: [ProviderLink]
    ) -> [DashboardMetricCardRow] {
        // #596: provider quick-link buttons live INSIDE the collapsible expanded section, pinned at its
        // bottom, so collapsing the caret hides them along with the expanded metrics — they're part of
        // the expander, not always-visible chrome. The caret shows for any provider with expanded
        // content (metrics OR links), so a links-only provider still gets a caret to reveal its buttons.
        let hasLinks = !links.isEmpty
        let hasExpandedContent = hasExpandedMetrics || hasLinks
        // OpenUsage's layout: the toggle sits between Always Visible and On Demand rows, so it stays put
        // while the section opens below it (and doubles as the drag target across that boundary).
        return alwaysRows.map(DashboardMetricCardRow.metric)
            + (hasExpandedContent ? [.divider] : [])
            + (isExpanded && !expandedRows.isEmpty ? expandedRows.map(DashboardMetricCardRow.metric) : [])
            + (isExpanded && hasLinks ? [.links(links)] : [])
    }

    private func expandedDividerID(for providerID: String) -> String {
        "\(providerID)::dashboard-expanded-divider"
    }

    private func visibleCondensedTextRowIDs(alwaysRows: [ResolvedRow], expandedRows: [ResolvedRow]) -> Set<String> {
        condensedTextRowIDs(alwaysRows).union(condensedTextRowIDs(expandedRows))
    }

    /// Neighbor-aware rule (shared with the share-card export via `WidgetData.condensedTextRowOffsets`):
    /// IDs of text-only rows sitting directly under another text-only row. Rows can't see their
    /// neighbors, so the list computes the pairs; Compact density pulls these rows up so a run of
    /// one-liners reads as one cluster. Called per segment (always-shown / expanded), so the expand
    /// caret is never crossed.
    private func condensedTextRowIDs(_ rows: [ResolvedRow]) -> Set<String> {
        let offsets = WidgetData.condensedTextRowOffsets(in: rows.map(\.data))
        return Set(offsets.map { rows[$0].descriptor.id })
    }

    /// A row folded into a Usage group, or a Top Models row with nothing to show.
    private func isHidden(_ row: ResolvedRow, usageRuns: UsageStatRuns) -> Bool {
        usageRuns.members.contains(row.descriptor.id)
            || (row.data.showsTopModels && TopModels.entries(from: row.data.modelBreakdown).isEmpty)
    }

    /// On Demand groups (resets, top models, usage) that sit under another visible row get the full group
    /// spacing above them; the first one under the caret sits closer (the caret already separates it).
    private func separatedGroupIDs(_ rows: [DashboardMetricCardRow], usageRuns: UsageStatRuns) -> Set<String> {
        var ids: Set<String> = []
        var previousIsRow = false
        for cardRow in rows {
            guard case .metric(let row) = cardRow else {
                previousIsRow = false
                continue
            }
            if isHidden(row, usageRuns: usageRuns) { continue }
            let isGroup = row.data.showsTopModels || row.data.showsResetExpiries
                || usageRuns.heads[row.descriptor.id] != nil
            if isGroup, previousIsRow { ids.insert(row.descriptor.id) }
            previousIsRow = true
        }
        return ids
    }

    private func row(_ descriptor: WidgetDescriptor, data: WidgetData, in providerID: String,
                     condensedTop: Bool, separatedAbove: Bool = false) -> some View {
        return WidgetRowView(
            data: data,
            onToggleResetDisplay: { dataStore.resetDisplayMode.toggle() },
            onToggleMeterStyle: { dataStore.meterStyle.toggle() },
            condensedTop: condensedTop,
            liveSweepFamily: animatedMetersEnabled && data.title.hasPrefix("Session") ? liveFamily(for: providerID) : nil,
            separatedAbove: separatedAbove,
            providerAccent: Self.accent(for: providerID)
        )
            .environment(\.resetClaim, resetClaims[providerID])
            .contentShape(Rectangle())
            .opacity(activeMetricID == descriptor.id ? 0 : 1)
            .highPriorityGesture(metricDragGesture(for: descriptor, providerID: providerID))
            .contextMenu { rowMenu(descriptor, providerID: providerID) }
            .reorderFrame(id: descriptor.id, in: .named(reorderSpaceName))
    }

    /// Desktop-native management for a single metric: hide it, pin/unpin it, refresh its provider, or jump
    /// into Customize — without a trip through Customize first. Hide leads (the most-reached-for verb), then
    /// star, then a divider before the two provider-/app-level actions.
    @ViewBuilder
    private func rowMenu(_ descriptor: WidgetDescriptor, providerID: String) -> some View {
        Button("Hide") {
            layout.setMetricEnabled(descriptor.id, false)
        }
        if descriptor.pinnable {
            Button(layout.isPinned(descriptor.id) ? "Unstar" : "Star for menu bar") {
                if layout.isPinned(descriptor.id) {
                    layout.setPinned(false, for: descriptor.id)
                } else if layout.canPin(descriptor.id) {
                    layout.setPinned(true, for: descriptor.id)
                } else {
                    layout.notePinDenied(descriptor.id)
                }
            }
        }
        Divider()
        if let provider = layout.provider(id: providerID) {
            Button("Refresh \(provider.displayName)") {
                Task { await dataStore.refreshOnUserRequest(providerID: providerID) }
            }
        }
        Button("Customize…") {
            openCustomize(for: providerID)
        }
    }

    /// From the dashboard, jump straight into this provider's Customize metrics (L2), not the provider list.
    private func openCustomize(for providerID: String) {
        withAnimation(Motion.modeSwitch) {
            layout.customizeProviderID = providerID
            layout.isEditing = true
        }
    }

    private func providerDragGesture(for group: ProviderGroup) -> some Gesture {
        reorderDragGesture(
            id: group.provider.id,
            coordinateSpaceName: reorderSpaceName,
            frameStore: frameStore,
            active: $activeProviderID,
            lift: $reorderLift,
            makeLift: { makeProviderLift(for: group, value: $0) },
            orderedIDs: { layout.displayGroups.map(\.provider.id) },
            reorder: { layout.reorderProvider(dragged: group.provider.id, target: $0) }
        )
    }

    private func metricDragGesture(for descriptor: WidgetDescriptor, providerID: String) -> some Gesture {
        reorderDragGesture(
            id: descriptor.id,
            coordinateSpaceName: reorderSpaceName,
            frameStore: frameStore,
            active: $activeMetricID,
            lift: $reorderLift,
            makeLift: { makeMetricLift(for: descriptor, value: $0) },
            orderedIDs: { metricTargetIDs(for: providerID) },
            reorder: { target in
                let current = metricTargetIDs(for: providerID)
                if current.contains(expandedDividerID(for: providerID)) {
                    guard let next = LayoutStore.reordered(current, dragged: descriptor.id, target: target) else {
                        return false
                    }
                    return layout.applyMetricDividerOrder(
                        next,
                        dragged: descriptor.id,
                        dividerID: expandedDividerID(for: providerID),
                        in: providerID
                    )
                }
                return layout.reorderMetric(dragged: descriptor.id, target: target, in: providerID)
            }
        )
    }

    private func metricTargetIDs(for providerID: String) -> [String] {
        guard let group = layout.displayGroups.first(where: { $0.provider.id == providerID }) else {
            return []
        }
        let alwaysShown = group.alwaysShownWidgets.compactMap { layout.descriptor(for: $0)?.id }
        // The caret is a drop target whenever the expanded section is open (Quotapus shows no quick-link
        // buttons, so only On Demand metrics open it).
        let hasExpandedContent = group.hasExpandedMetrics
        guard hasExpandedContent, layout.isProviderExpanded(providerID) else { return alwaysShown }
        let expanded = group.expandedWidgets.compactMap { layout.descriptor(for: $0)?.id }
        return alwaysShown + [expandedDividerID(for: providerID)] + expanded
    }

    private func makeProviderLift(for group: ProviderGroup, value: DragGesture.Value) -> ReorderLift? {
        // The floating preview should match what the card shows: only the always-shown rows unless this
        // provider's caret is currently open.
        let isExpanded = layout.isProviderExpanded(group.provider.id)
        let visibleWidgets = isExpanded ? group.widgets : group.alwaysShownWidgets
        let rows = visibleWidgets.compactMap { widget -> WidgetData? in
            guard let descriptor = layout.descriptor(for: widget) else { return nil }
            return dataStore.data(for: descriptor)
        }
        let alwaysCount = group.alwaysShownWidgets.compactMap { layout.descriptor(for: $0) }.count
        return ReorderLift.make(
            id: group.provider.id,
            payload: .dashboardProvider(
                provider: group.provider,
                plan: dataStore.plan(for: group.provider.id),
                rows: rows,
                dividerIndex: isExpanded && group.hasExpandedMetrics ? alwaysCount : nil,
                // Quotapus's toggle sits between the two groups, so the lift only draws the bottom
                // caret while that is where the toggle is: on a collapsed card.
                links: [],
                showsCaret: group.hasExpandedMetrics && !isExpanded,
                isExpanded: isExpanded
            ),
            value: value,
            frames: frameStore.frames
        )
    }

    private func makeMetricLift(for descriptor: WidgetDescriptor, value: DragGesture.Value) -> ReorderLift? {
        ReorderLift.make(
            id: descriptor.id,
            payload: .dashboardMetric(data: dataStore.data(for: descriptor)),
            value: value,
            frames: frameStore.frames
        )
    }
}

/// The centered caret between a provider's Always Visible and On Demand rows (OpenUsage's layout), made
/// smoother: the whole row is the button, it lights softly under the pointer with the same fill and
/// easing as the live card headers, and the chevron turns with the spring that opens the section.
private struct OnDemandToggle: View {
    let isExpanded: Bool
    let toggle: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: toggle) {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .foregroundStyle(hovered ? .secondary : .tertiary)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(Color.primary.opacity(hovered ? 0.06 : 0),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .animation(Motion.spring, value: isExpanded)
        .accessibilityLabel(isExpanded ? "Show Less" : "Show More")
    }
}
