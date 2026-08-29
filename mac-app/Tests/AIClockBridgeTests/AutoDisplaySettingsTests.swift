import XCTest
@testable import AIClockBridge

final class AutoDisplaySettingsTests: XCTestCase {
    func testFormValuesRoundTripEveryControlAndNormalizeScheduledNumbers() {
        let values = AutoDisplaySettingsFormValues(
            claudeEnabled: true,
            codexEnabled: false,
            approvalEnabled: false,
            musicEnabled: true,
            weatherEnabled: false,
            weatherIntervalMinutes: 0,
            weatherDurationSeconds: 4,
            quoteEnabled: true,
            quoteIntervalMinutes: 17,
            quoteDurationSeconds: 22,
            stockEnabled: true,
            stockIntervalMinutes: 500,
            stockDurationSeconds: 90,
            netEnabled: true,
            netIntervalMinutes: 8,
            netDurationSeconds: 9
        )

        let configuration = values.configuration()

        XCTAssertEqual(configuration.events, [
            .claude: true, .codex: false, .approval: false, .music: true,
        ])
        XCTAssertEqual(configuration.scheduled[.weather],
                       .init(enabled: false, intervalSeconds: 60, durationSeconds: 5))
        XCTAssertEqual(configuration.scheduled[.quote],
                       .init(enabled: true, intervalSeconds: 1_020, durationSeconds: 22))
        XCTAssertEqual(configuration.scheduled[.stock],
                       .init(enabled: true, intervalSeconds: 14_400, durationSeconds: 60))
        XCTAssertEqual(configuration.scheduled[.net],
                       .init(enabled: true, intervalSeconds: 480, durationSeconds: 9))
    }

    func testFormValuesLoadAllSavedFieldsInDisplayUnits() {
        var configuration = AutoDisplayConfiguration.defaults
        configuration.events = [.claude: true, .codex: false, .approval: false, .music: false]
        configuration.scheduled = [
            .weather: .init(enabled: false, intervalSeconds: 120, durationSeconds: 5),
            .quote: .init(enabled: false, intervalSeconds: 1_200, durationSeconds: 15),
            .stock: .init(enabled: true, intervalSeconds: 3_600, durationSeconds: 25),
            .net: .init(enabled: true, intervalSeconds: 7_200, durationSeconds: 35),
        ]

        let values = AutoDisplaySettingsFormValues(configuration: configuration)

        XCTAssertTrue(values.claudeEnabled)
        XCTAssertFalse(values.codexEnabled)
        XCTAssertFalse(values.approvalEnabled)
        XCTAssertFalse(values.musicEnabled)
        XCTAssertEqual(values.weatherIntervalMinutes, 2)
        XCTAssertEqual(values.weatherDurationSeconds, 5)
        XCTAssertEqual(values.quoteIntervalMinutes, 20)
        XCTAssertEqual(values.quoteDurationSeconds, 15)
        XCTAssertEqual(values.stockIntervalMinutes, 60)
        XCTAssertEqual(values.stockDurationSeconds, 25)
        XCTAssertEqual(values.netIntervalMinutes, 120)
        XCTAssertEqual(values.netDurationSeconds, 35)
    }

    func testStatusPayloadContainsAutoDisplayConfiguration() {
        let store = AutoDisplaySettingsStore(defaults: .standard)
        let payload = StatusPayloadComposer.addAutoDisplay(["version": "test"], settings: store)

        XCTAssertNotNil(payload["auto_display"] as? [String: Any])
    }

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

    func testJSONContainsStableIDKeyedEventAndScheduledObjects() throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AutoDisplaySettingsStore(defaults: defaults)

        let object = store.jsonObject()
        let events = try XCTUnwrap(object["events"] as? [String: Any])
        let scheduled = try XCTUnwrap(object["scheduled"] as? [String: Any])
        let weather = try XCTUnwrap(scheduled["weather"] as? [String: Any])
        let quote = try XCTUnwrap(scheduled["quote"] as? [String: Any])

        XCTAssertEqual(Set(events.keys), Set(["claude", "codex", "approval", "music"]))
        XCTAssertEqual(Set(scheduled.keys), Set(["weather", "quote", "stock", "net"]))
        XCTAssertEqual(events["claude"] as? Bool, false)
        XCTAssertEqual(events["codex"] as? Bool, true)
        XCTAssertEqual(weather["enabled"] as? Bool, true)
        XCTAssertEqual(weather["interval_seconds"] as? Int, 900)
        XCTAssertEqual(weather["duration_seconds"] as? Int, 10)
        XCTAssertEqual(quote["enabled"] as? Bool, true)
        XCTAssertEqual(quote["interval_seconds"] as? Int, 1800)
        XCTAssertEqual(quote["duration_seconds"] as? Int, 12)
    }
}
