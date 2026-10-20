import Foundation

/// `@AppStorage` keys for the Live Activity surfaces (defaults confirmed in the redesign spec).
enum LiveActivitySettings {
    static let cardKey = "quotapus.live.card"                         // default true
    static let headerSpeedKey = "quotapus.live.headerSpeed"           // default true
    static let animatedMetersKey = "quotapus.live.animatedMeters"     // default true
    static let collapsedKey = "quotapus.activity.collapsed"           // default false
    static let tokensCardKey = "quotapus.live.tokensCard"             // default true
    static let modelsCardKey = "quotapus.live.modelsCard"             // default true
    static let spendCardKey = "quotapus.live.spendCard"               // default true
    static let spendCollapsedKey = "quotapus.spend.collapsed"         // default true (one line)
    static let tokensPeriodKey = "quotapus.tokens.period"             // CardPeriod.rawValue, default "today"
    static let spendPeriodKey = "quotapus.spend.period"               // CardPeriod.rawValue, default "today"
    static let modelsPeriodKey = "quotapus.models.period"             // CardPeriod.rawValue, default "today"
    static let tokensCollapsedKey = "quotapus.tokens.collapsed"       // default true (one line)
    static let modelsCollapsedKey = "quotapus.models.collapsed"       // default true (one line)

    /// Every key, for Reset All Settings.
    static let allKeys = [cardKey, headerSpeedKey, animatedMetersKey,
                          collapsedKey, tokensCardKey, modelsCardKey, tokensCollapsedKey, modelsCollapsedKey,
                          spendCardKey, spendCollapsedKey, tokensPeriodKey, spendPeriodKey, modelsPeriodKey]

    /// The defaults the `@AppStorage` properties declare, kept here so tests and docs agree with them.
    static let defaults: [String: any Sendable] = [
        cardKey: true, headerSpeedKey: true, animatedMetersKey: true, collapsedKey: false,
        tokensCardKey: true, modelsCardKey: true, tokensCollapsedKey: true, modelsCollapsedKey: true,
        spendCardKey: true, spendCollapsedKey: true,
        tokensPeriodKey: CardPeriod.today.rawValue, spendPeriodKey: CardPeriod.today.rawValue,
        modelsPeriodKey: CardPeriod.today.rawValue,
    ]

    /// Reset All Settings: removing a key restores its `@AppStorage` default.
    static func reset(in store: UserDefaults = .standard) {
        for key in allKeys { store.removeObject(forKey: key) }
    }
}

enum ActivityBreakdown: String, CaseIterable {
    case providers = "Providers"
    case devices = "Devices"
}

/// Compact number formats shared by the Activity card and the header chips.
/// Compact counts for the live surfaces: three significant digits with an uppercase K / M / B
/// suffix ("9.12K", "40.9M", "409M", "1.23B"). Uppercase on purpose: a lowercase "m" already means
/// minutes in this UI ("12m ago").
enum LiveFormat {
    static func rate(_ perMinute: Double) -> String { compact(perMinute) }

    static func tokens(_ value: Int) -> String { compact(Double(value)) }

    static func compact(_ value: Double) -> String {
        let magnitude = abs(value)
        let (scaled, suffix): (Double, String) = switch magnitude {
        case 999_500_000...: (value / 1_000_000_000, "B")
        case 999_500...: (value / 1_000_000, "M")
        case 999.5...: (value / 1_000, "K")
        default: (value, "")
        }
        guard !suffix.isEmpty else { return "\(Int(value.rounded()))" }
        let digits = abs(scaled) >= 99.95 ? 0 : abs(scaled) >= 9.995 ? 1 : 2
        return String(format: "%.\(digits)f", scaled) + suffix
    }

    /// Dollars for a card: cents under $100, whole dollars under $1,000, then compact ("$4.20", "$146",
    /// "$2.38K"), so a headline never outgrows the shared number slot.
    static func dollars(_ value: Double) -> String {
        if abs(value) >= 999.5 { return "$" + compact(value) }
        return Formatters.currency(value, fractionDigits: value < 100 ? 2 : 0)
    }
}
