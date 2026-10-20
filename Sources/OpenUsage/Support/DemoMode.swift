import Foundation

/// Demo mode for README recordings and screenshots: the real dashboard, fed from a sample-data file
/// instead of this Mac's accounts, logs, and SSH devices. Launch a dev build with
/// `QUOTAPUS_DEMO_FIXTURE=/path/to/fixture.json` (see `script/demo/`). Nothing here runs unless that
/// variable is set: no Keychain reads, no provider requests, no SSH, no log tails.
struct DemoFixture: Decodable, Sendable {
    /// Quota lines plus `usageHistory`; the spend rows are rendered from the history at refresh time
    /// with the same renderer the providers use, so they read exactly like real ones.
    var snapshots: [ProviderSnapshot]
    var devices: [RemoteUsageDevice]
    var documents: [UsageHistoryDocument]
    /// Tokens per minute on this Mac, keyed by `LiveFamily` raw value.
    var liveRates: [String: Double]
    /// Tokens per minute per remote device id, keyed by `LiveFamily` raw value.
    var deviceLiveRates: [String: [String: Double]]
}

@MainActor
enum DemoMode {
    static let environmentKey = "QUOTAPUS_DEMO_FIXTURE"

    /// Loaded once. A set but unreadable fixture stops the launch: recording real data by accident is
    /// the one outcome demo mode exists to prevent.
    static let fixture: DemoFixture? = {
        guard let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let fixture = try decoder.decode(DemoFixture.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            AppLog.info(.config, "demo mode: sample data from \(path)")
            return fixture
        } catch {
            AppLog.error(.config, "demo mode: fixture \(path) couldn't be read: \(error)")
            fatalError("Demo fixture \(path) couldn't be read: \(error)")
        }
    }()

    static var isActive: Bool { fixture != nil }

    /// Every provider keeps its real descriptors; only the ones in the fixture report credentials and data.
    static func wrap(_ providers: [ProviderRuntime], fixture: DemoFixture) -> [ProviderRuntime] {
        let registry = WidgetRegistry.from(providers)
        return providers.map { base in
            let id = base.provider.id
            return DemoProviderRuntime(
                base: base,
                fixture: fixture.snapshots.first { $0.providerID == id },
                history: registry.historyDescriptorsByProvider[id]
            )
        }
    }

    /// Turns on exactly the fixture's providers and skips the first-run hint card.
    static func enableFixtureProviders(_ fixture: DemoFixture, providers: [ProviderRuntime],
                                       enablement: ProviderEnablementStore, onboarding: OnboardingStore) {
        enablement.registerKnownProviders(Set(providers.map(\.provider.id)))
        enablement.seedEnabledProviders(Set(fixture.snapshots.map(\.providerID)))
        onboarding.dismissCustomizeHint()
    }

    static func liveTails(_ fixture: DemoFixture) -> [LiveFamily: any LiveTailSource] {
        Dictionary(uniqueKeysWithValues: LiveFamily.allCases.map { family in
            (family, DemoLiveTail(tokensPerMinute: fixture.liveRates[family.rawValue] ?? 0,
                                  phase: Double(family.rawValue.count)))
        })
    }

    /// Stands in for the SSH import: the fixture's summary, stamped now, plus a fresh live sample.
    static func remoteFetcher(_ fixture: DemoFixture) -> @Sendable (RemoteUsageDevice) async throws -> RemoteFetchResult {
        { device in
            guard var document = fixture.documents.first(where: { $0.deviceID == device.id }) else {
                throw SSHRemoteUsageError.commandFailed("Demo fixture has no history for \(device.name).")
            }
            let now = Date()
            document.updatedAt = now
            var buckets: [LiveFamily: LiveRateBuckets] = [:]
            for family in LiveFamily.allCases {
                let rate = fixture.deviceLiveRates[device.id]?[family.rawValue] ?? 0
                buckets[family] = DemoLiveTail.backfilled(tokensPerMinute: rate, phase: Double(device.id.count), now: now)
            }
            return RemoteFetchResult(document: document,
                                     liveSample: RemoteLiveSample(deviceID: device.id, importedAt: now, familyBuckets: buckets))
        }
    }
}

/// A provider card that shows fixture data through the real descriptors and spend renderer.
@MainActor
final class DemoProviderRuntime: ProviderRuntime {
    private let base: ProviderRuntime
    private let fixture: ProviderSnapshot?
    private let history: UsageHistoryDescriptor?

    init(base: ProviderRuntime, fixture: ProviderSnapshot?, history: UsageHistoryDescriptor?) {
        self.base = base
        self.fixture = fixture
        self.history = history
    }

    var provider: Provider { base.provider }
    var widgetDescriptors: [WidgetDescriptor] { base.widgetDescriptors }

    func refresh() async -> ProviderSnapshot {
        guard var snapshot = fixture else {
            return ProviderSnapshot(providerID: provider.id, displayName: provider.displayName, lines: [])
        }
        let now = Date()
        snapshot.refreshedAt = now
        if let history, let usage = snapshot.usageHistory {
            snapshot = UsageHistorySnapshotRenderer.render(local: snapshot, history: usage, descriptor: history,
                                                           now: now, combined: false)
        }
        return snapshot
    }

    func hasLocalCredentials() async -> Bool { fixture != nil }
}

/// Live speed that wanders around a target rate, deterministic for a given wall-clock time.
actor DemoLiveTail: LiveTailSource {
    private static let step: TimeInterval = 2
    private let tokensPerMinute: Double
    private let phase: Double
    private var buckets: LiveRateBuckets?
    private var lastStep: Int?

    init(tokensPerMinute: Double, phase: Double) {
        self.tokensPerMinute = tokensPerMinute
        self.phase = phase
    }

    func poll(now: Date) async -> LiveRateBuckets {
        let current = Self.stepIndex(now)
        guard var next = buckets, let lastStep else {
            buckets = Self.backfilled(tokensPerMinute: tokensPerMinute, phase: phase, now: now)
            lastStep = current
            return buckets!
        }
        for index in (lastStep + 1)..<max(lastStep + 1, current + 1) {
            let at = Date(timeIntervalSince1970: Double(index) * Self.step)
            next.add(tokens: Self.tokens(at: at, tokensPerMinute: tokensPerMinute, phase: phase), at: at, now: now)
        }
        buckets = next
        self.lastStep = current
        return next
    }

    static func backfilled(tokensPerMinute: Double, phase: Double, now: Date) -> LiveRateBuckets {
        var buckets = LiveRateBuckets(now: now)
        let end = stepIndex(now)
        let start = end - Int(LiveLogTail.window / step)
        for index in start...end {
            let at = Date(timeIntervalSince1970: Double(index) * step)
            buckets.add(tokens: tokens(at: at, tokensPerMinute: tokensPerMinute, phase: phase), at: at, now: now)
        }
        return buckets
    }

    private static func stepIndex(_ date: Date) -> Int { Int(date.timeIntervalSince1970 / step) }

    /// Slow swells plus short bursts, so the chart looks like real agent sessions rather than a flat line.
    private static func tokens(at date: Date, tokensPerMinute: Double, phase: Double) -> Int {
        let x = date.timeIntervalSince1970
        let swell = 1 + 0.35 * sin(x / 190 + phase) + 0.2 * sin(x / 53 + phase * 2.3)
        let burst = sin(x / 11 + phase) > 0.85 ? 1.6 : 1
        return Int(tokensPerMinute / 60 * step * max(0.15, swell * burst))
    }
}
