import Foundation

protocol AutoDisplaySettingsPersistence: AnyObject {
    func data(forKey key: String) -> Data?
    func integer(forKey key: String) -> Int
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: AutoDisplaySettingsPersistence {}

enum AutoDisplayItemID: String, Codable, CaseIterable {
    case claude, codex, approval, music, weather, quote, stock, net
}

struct ScheduledDisplaySetting: Codable, Equatable {
    var enabled: Bool
    var intervalSeconds: Int
    var durationSeconds: Int
}

struct AutoDisplayConfiguration: Codable, Equatable {
    var events: [AutoDisplayItemID: Bool]
    var scheduled: [AutoDisplayItemID: ScheduledDisplaySetting]

    static let defaults = AutoDisplayConfiguration(
        events: [
            .claude: false,
            .codex: true,
            .approval: true,
            .music: true,
        ],
        scheduled: [
            .weather: .init(enabled: true, intervalSeconds: 900, durationSeconds: 10),
            .quote: .init(enabled: true, intervalSeconds: 1800, durationSeconds: 12),
            .stock: .init(enabled: false, intervalSeconds: 900, durationSeconds: 10),
            .net: .init(enabled: false, intervalSeconds: 600, durationSeconds: 10),
        ]
    )

    mutating func normalize() {
        for (key, value) in Self.defaults.events where events[key] == nil {
            events[key] = value
        }
        for (key, value) in Self.defaults.scheduled where scheduled[key] == nil {
            scheduled[key] = value
        }
        for key in [AutoDisplayItemID.weather, .quote, .stock, .net] {
            guard var item = scheduled[key] else { continue }
            item.intervalSeconds = min(14_400, max(60, item.intervalSeconds))
            item.durationSeconds = min(60, max(5, item.durationSeconds))
            scheduled[key] = item
        }
    }
}

final class AutoDisplaySettingsStore {
    private static let configurationKey = "auto_display_configuration_v1"
    private static let revisionKey = "auto_display_revision"

    private struct State {
        var configuration: AutoDisplayConfiguration
        var revision: Int
    }

    private let persistence: AutoDisplaySettingsPersistence
    private let lock = NSLock()
    private var state: State

    var configuration: AutoDisplayConfiguration { withStateLock { state.configuration } }
    var revision: Int { withStateLock { state.revision } }

    convenience init(defaults: UserDefaults = .standard) {
        self.init(persistence: defaults)
    }

    init(persistence: AutoDisplaySettingsPersistence) {
        self.persistence = persistence
        self.state = State(
            configuration: Self.loadConfiguration(from: persistence),
            revision: persistence.integer(forKey: Self.revisionKey)
        )
    }

    @discardableResult
    func save(_ configuration: AutoDisplayConfiguration) -> Bool {
        var normalizedConfiguration = configuration
        normalizedConfiguration.normalize()

        guard let data = try? JSONEncoder().encode(normalizedConfiguration) else { return false }

        return withStateLock {
            let previousData = persistence.data(forKey: Self.configurationKey)
            let previousRevision = persistence.integer(forKey: Self.revisionKey)
            let nextRevision = state.revision + 1
            persistence.set(data, forKey: Self.configurationKey)
            persistence.set(nextRevision, forKey: Self.revisionKey)

            guard persistence.data(forKey: Self.configurationKey) == data,
                  persistence.integer(forKey: Self.revisionKey) == nextRevision else {
                persistence.set(previousData, forKey: Self.configurationKey)
                persistence.set(previousRevision, forKey: Self.revisionKey)
                return false
            }

            state = State(configuration: normalizedConfiguration, revision: nextRevision)
            return true
        }
    }

    func jsonObject() -> [String: Any] {
        let snapshot = withStateLock { state }
        let events = Dictionary(uniqueKeysWithValues: snapshot.configuration.events.map { ($0.key.rawValue, $0.value) })
        let scheduled = Dictionary(uniqueKeysWithValues: snapshot.configuration.scheduled.map { key, value in
            (
                key.rawValue,
                [
                    "enabled": value.enabled,
                    "interval_seconds": value.intervalSeconds,
                    "duration_seconds": value.durationSeconds,
                ] as [String: Any]
            )
        })
        return ["events": events, "scheduled": scheduled, "revision": snapshot.revision]
    }

    private static func loadConfiguration(from persistence: AutoDisplaySettingsPersistence) -> AutoDisplayConfiguration {
        guard let data = persistence.data(forKey: configurationKey),
              var configuration = try? JSONDecoder().decode(AutoDisplayConfiguration.self, from: data)
        else {
            return .defaults
        }
        configuration.normalize()
        return configuration
    }

    private func withStateLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }
}
