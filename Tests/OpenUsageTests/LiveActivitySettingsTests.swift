import XCTest
@testable import OpenUsage

final class LiveActivitySettingsTests: XCTestCase {
    func testResetAllRestoresLiveDefaults() throws {
        let suite = "LiveActivitySettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: LiveActivitySettings.cardKey)
        defaults.set(false, forKey: LiveActivitySettings.headerSpeedKey)
        defaults.set(false, forKey: LiveActivitySettings.animatedMetersKey)
        defaults.set(true, forKey: LiveActivitySettings.collapsedKey)
        defaults.set(false, forKey: LiveActivitySettings.tokensCardKey)
        defaults.set(false, forKey: LiveActivitySettings.modelsCollapsedKey)
        defaults.set(false, forKey: LiveActivitySettings.spendCardKey)
        defaults.set("thirtyDays", forKey: LiveActivitySettings.tokensPeriodKey)

        LiveActivitySettings.reset(in: defaults)

        for key in LiveActivitySettings.allKeys {
            XCTAssertNil(defaults.object(forKey: key), "\(key) should fall back to its @AppStorage default")
        }
        XCTAssertEqual(LiveActivitySettings.defaults[LiveActivitySettings.cardKey] as? Bool, true)
        XCTAssertEqual(LiveActivitySettings.defaults[LiveActivitySettings.tokensCardKey] as? Bool, true)
        XCTAssertEqual(LiveActivitySettings.defaults[LiveActivitySettings.modelsCardKey] as? Bool, true)
        XCTAssertEqual(LiveActivitySettings.defaults[LiveActivitySettings.tokensCollapsedKey] as? Bool, true)
        XCTAssertEqual(LiveActivitySettings.defaults[LiveActivitySettings.spendCardKey] as? Bool, true)
        XCTAssertEqual(LiveActivitySettings.defaults[LiveActivitySettings.modelsPeriodKey] as? String, "today")
    }
}
