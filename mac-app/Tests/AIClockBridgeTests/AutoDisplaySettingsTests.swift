import XCTest
@testable import AIClockBridge

final class AutoDisplaySettingsTests: XCTestCase {
    func testDefaultsMatchProductDecision() {
        let configuration = AutoDisplayConfiguration.defaults

        XCTAssertFalse(configuration.events[.claude]!)
        XCTAssertTrue(configuration.events[.codex]!)
        XCTAssertTrue(configuration.events[.approval]!)
        XCTAssertTrue(configuration.events[.music]!)
        XCTAssertEqual(
            configuration.scheduled[.weather],
            .init(enabled: true, intervalSeconds: 900, durationSeconds: 10)
        )
        XCTAssertEqual(
            configuration.scheduled[.quote],
            .init(enabled: true, intervalSeconds: 1800, durationSeconds: 12)
        )
        XCTAssertEqual(configuration.scheduled[.stock]?.enabled, false)
        XCTAssertEqual(configuration.scheduled[.net]?.enabled, false)
    }

    func testNormalizeClampsScheduledValues() {
        var configuration = AutoDisplayConfiguration.defaults
        configuration.scheduled[.quote] = .init(enabled: true, intervalSeconds: 1, durationSeconds: 999)

        configuration.normalize()

        XCTAssertEqual(configuration.scheduled[.quote]?.intervalSeconds, 60)
        XCTAssertEqual(configuration.scheduled[.quote]?.durationSeconds, 60)
    }

    func testStorePersistsNormalizedConfigurationAndIncrementsRevision() throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AutoDisplaySettingsStore(defaults: defaults)
        var configuration = store.configuration
        configuration.events[.claude] = true
        configuration.scheduled[.quote] = .init(enabled: true, intervalSeconds: 1, durationSeconds: 999)
        let oldRevision = store.revision

        store.save(configuration)

        let reloaded = AutoDisplaySettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.configuration.events[.claude]!)
        XCTAssertEqual(reloaded.configuration.scheduled[.quote]?.intervalSeconds, 60)
        XCTAssertEqual(reloaded.configuration.scheduled[.quote]?.durationSeconds, 60)
        let storedData = try XCTUnwrap(defaults.data(forKey: "auto_display_configuration_v1"))
        let storedConfiguration = try JSONDecoder().decode(AutoDisplayConfiguration.self, from: storedData)
        XCTAssertEqual(storedConfiguration.scheduled[.quote]?.intervalSeconds, 60)
        XCTAssertEqual(storedConfiguration.scheduled[.quote]?.durationSeconds, 60)
        XCTAssertGreaterThan(store.revision, oldRevision)
        XCTAssertEqual(store.jsonObject()["revision"] as? Int, store.revision)
    }
}
