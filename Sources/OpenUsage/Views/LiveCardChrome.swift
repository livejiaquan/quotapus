import SwiftUI

/// The header row shared by the Activity, Tokens, and Models cards. The whole row is the expand /
/// collapse button. Its trailing chevron follows the macOS sidebar section headers: it points right
/// while collapsed and turns down when open, in a quiet tertiary tone that brightens on hover, next to
/// a soft fill that shows the row is clickable. While the card is open the chevron stays hidden until
/// the pointer is over the header, so an open card reads clean and the way back appears on hover. The row reaches the card's edges (the card's insets are
/// inside it), so the fill lights the whole collapsed card, or the full-width header strip when open;
/// the card clips it to its rounded shape.
struct LiveCardHeader<Content: View>: View {
    @Binding var collapsed: Bool
    /// For the log line and the hint, e.g. "activity".
    let name: String
    @ViewBuilder let content: Content

    @State private var hovered = false

    var body: some View {
        Button {
            AppLog.info(.statusItem, "ui: \(collapsed ? "expand" : "collapse") \(name)")
            collapsed.toggle()
        } label: {
            HStack(alignment: .center, spacing: 6) {
                content
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                    .foregroundStyle(hovered ? .secondary : .tertiary)
                    .opacity(collapsed || hovered ? 1 : 0)
                    .frame(width: 12)
                    .padding(.leading, 4)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 30)
            .padding(.horizontal, LiveCardStyle.horizontalInset)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(hovered ? 0.06 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .accessibilityHint(collapsed ? "Shows \(name) details" : "Hides \(name) details")
    }
}

enum LiveCardStyle {
    /// The big number in a live card's header: smaller once collapsed to one line.
    static func headlineFont(collapsed: Bool, density: DensitySetting) -> Font {
        .system(size: collapsed ? (density == .compact ? 15 : 17) : (density == .compact ? 20 : 24), weight: .semibold)
    }

    /// The small chart a collapsed card keeps on its header line: one size on every card, so the charts
    /// and chevrons line up in a column.
    static let collapsedChartWidth: CGFloat = 80
    /// The card's side inset; the header row applies it inside itself, the details beside it.
    static let horizontalInset: CGFloat = 12
    static let collapsedChartHeight: CGFloat = 22
    /// The leading slot the Activity card's live dot occupies; the other cards keep it empty so every
    /// headline number starts at the same x.
    static let leadingSlotWidth: CGFloat = 6
    /// Shared between a card's collapsed chart and its expanded one, so opening the card moves the
    /// small chart down and grows it into the big one.
    static let chartGeometryID = "chart"
}

/// A card header's number and unit. The number sits in a slot as wide as the widest headline any card
/// prints ("$8.88K"), so every card's unit starts at the same x and stays put as the number ticks; the
/// unit shares the number's text baseline instead of floating at its vertical center.
struct LiveCardFigure: View {
    let value: String
    let unit: String
    var collapsed: Bool
    var dimmed = false

    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    static let widestValue = "$8.88K"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            ZStack(alignment: .leading) {
                Text(Self.widestValue).hidden().accessibilityHidden(true)
                Text(value)
                    .foregroundStyle(dimmed ? .secondary : .primary)
                    .contentTransition(.numericText())
            }
            .font(LiveCardStyle.headlineFont(collapsed: collapsed, density: density))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            Text(unit)
                .font(.system(size: density.supportingPointSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .layoutPriority(1)
    }
}

extension View {
    /// Right-click "Hide … Card", like hiding a provider row: turns the card's Live Activity switch off.
    /// Settings → Live Activity brings it back.
    func liveCardHideMenu(_ title: String, settingKey: String) -> some View {
        contextMenu {
            Button("Hide \(title)") {
                AppLog.info(.statusItem, "ui: hide \(title)")
                UserDefaults.standard.set(false, forKey: settingKey)
            }
        }
    }
}

/// The empty leading slot for cards without a live dot.
struct LiveCardLeadingSlot: View {
    var body: some View {
        Color.clear.frame(width: LiveCardStyle.leadingSlotWidth, height: LiveCardStyle.leadingSlotWidth)
            .accessibilityHidden(true)
    }
}

/// Daily totals as thin bars, oldest first, each stacked by provider in its brand color (largest
/// provider at the bottom). The highlighted bar (the selected day) is drawn at full strength; with none
/// highlighted (30 Days) every bar shares one strong-but-not-full strength.
struct DailyBarsChart: View {
    let layers: [(values: [Double], color: Color)]
    var highlighted: Int?

    var body: some View {
        Canvas { context, size in
            guard let count = layers.first?.values.count, count > 0 else { return }
            let totals = (0..<count).map { index in layers.reduce(0) { $0 + ($1.values[safe: index] ?? 0) } }
            let peak = totals.max() ?? 0
            let gap: CGFloat = count > 20 ? 1 : 2
            let width = max(1, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            // A faint baseline instead of stub bars on days with nothing, so quiet days read as empty.
            context.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)),
                         with: .color(.primary.opacity(0.12)))
            guard peak > 0 else { return }
            for index in 0..<count where totals[index] > 0 {
                let x = CGFloat(index) * (width + gap)
                let barHeight = max(1.5, size.height * CGFloat(totals[index] / peak))
                let opacity = highlighted.map { $0 == index ? 1 : 0.4 } ?? 0.8
                // Clip the stack to one rounded bar so the segments read as a single column.
                var column = context
                column.clip(to: Path(roundedRect: CGRect(x: x, y: size.height - barHeight, width: width, height: barHeight),
                                     cornerRadius: min(1.5, width / 2)))
                var y = size.height
                for layer in layers {
                    let value = layer.values[safe: index] ?? 0
                    guard value > 0 else { continue }
                    let segment = barHeight * CGFloat(value / totals[index])
                    y -= segment
                    column.fill(Path(CGRect(x: x, y: y, width: width, height: segment)),
                                with: .color(layer.color.opacity(opacity)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
