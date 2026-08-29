import XCTest
@testable import AIClockBridge

final class WeatherMonitorTests: XCTestCase {
    private let city = WeatherCity(name: "成都", admin1: "四川", latitude: 30.66667,
                                   longitude: 104.06667, timezone: "Asia/Shanghai")

    func testWeatherCodesMapToSupportedIcons() {
        XCTAssertEqual(WeatherMonitor.icon(for: 0), .clear)
        XCTAssertEqual(WeatherMonitor.icon(for: 2), .partlyCloudy)
        XCTAssertEqual(WeatherMonitor.icon(for: 3), .overcast)
        XCTAssertEqual(WeatherMonitor.icon(for: 45), .fog)
        XCTAssertEqual(WeatherMonitor.icon(for: 61), .rain)
        XCTAssertEqual(WeatherMonitor.icon(for: 80), .showers)
        XCTAssertEqual(WeatherMonitor.icon(for: 71), .snow)
        XCTAssertEqual(WeatherMonitor.icon(for: 95), .thunderstorm)
        XCTAssertEqual(WeatherMonitor.icon(for: 999), .unknown)
    }

    func testWindDirectionUsesEightSectorsAtBoundaries() {
        XCTAssertEqual(WeatherMonitor.windDirection(degrees: 0), "北")
        XCTAssertEqual(WeatherMonitor.windDirection(degrees: 22), "北")
        XCTAssertEqual(WeatherMonitor.windDirection(degrees: 23), "东北")
        XCTAssertEqual(WeatherMonitor.windDirection(degrees: 225), "西南")
        XCTAssertEqual(WeatherMonitor.windDirection(degrees: 359), "北")
    }

    func testAQIGradeUsesUSCategoryBoundaries() {
        XCTAssertEqual(WeatherMonitor.aqiGrade(50), "优")
        XCTAssertEqual(WeatherMonitor.aqiGrade(51), "良")
        XCTAssertEqual(WeatherMonitor.aqiGrade(100), "良")
        XCTAssertEqual(WeatherMonitor.aqiGrade(101), "轻度")
        XCTAssertEqual(WeatherMonitor.aqiGrade(151), "中度")
        XCTAssertEqual(WeatherMonitor.aqiGrade(201), "重度")
        XCTAssertEqual(WeatherMonitor.aqiGrade(301), "严重")
    }

    func testParseWeatherUsesRemainingHoursAndNextThreeDays() throws {
        let weather = Data(#"""
        {
          "current": {
            "time": "2026-08-29T14:00", "temperature_2m": 26.1,
            "relative_humidity_2m": 68, "apparent_temperature": 28.0,
            "weather_code": 3, "wind_speed_10m": 8.4, "wind_direction_10m": 225
          },
          "hourly": {
            "time": ["2026-08-29T13:00", "2026-08-29T14:00", "2026-08-29T15:00", "2026-08-29T16:00"],
            "precipitation_probability": [90, 10, 35, 20]
          },
          "daily": {
            "time": ["2026-08-29", "2026-08-30", "2026-08-31", "2026-09-01", "2026-09-02"],
            "weather_code": [3, 2, 61, 0, 45],
            "temperature_2m_max": [29.2, 28, 25, 30, 22],
            "temperature_2m_min": [21.3, 20, 19, 21, 17],
            "precipitation_probability_max": [90, 40, 80, 5, 10]
          }
        }
        """#.utf8)
        let air = Data(#"""
        {"hourly":{"time":["2026-08-29T13:00","2026-08-29T14:00","2026-08-29T15:00"],"us_aqi":[38,42,44]}}
        """#.utf8)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-29T06:30:00Z"))

        let snapshot = try WeatherMonitor.parseWeather(
            weatherData: weather, airData: air, city: city, now: now, textRev: 7)

        XCTAssertEqual(snapshot.city, "成都")
        XCTAssertEqual(snapshot.temperature, 26.1)
        XCTAssertEqual(snapshot.high, 29.2)
        XCTAssertEqual(snapshot.precipitationProbability, 35)
        XCTAssertEqual(snapshot.windDirection, "西南")
        XCTAssertEqual(snapshot.aqi, 42)
        XCTAssertEqual(snapshot.forecast, [
            WeatherForecastDay(day: "明天", code: 2, high: 28, low: 20),
            WeatherForecastDay(day: "周一", code: 61, high: 25, low: 19),
            WeatherForecastDay(day: "周二", code: 0, high: 30, low: 21),
        ])
        XCTAssertEqual(snapshot.textRev, 7)
    }

    func testSerializedWeatherPreservesMissingValuesAndComputesStaleness() throws {
        let updated = Date(timeIntervalSince1970: 1_000)
        let snapshot = WeatherSnapshot(
            city: "成都", updatedAt: updated, weatherCode: 3, temperature: nil,
            apparentTemperature: nil, high: nil, low: nil, humidity: nil,
            precipitationProbability: nil, windSpeed: nil, windDirectionDegrees: nil,
            windDirection: "--", aqi: nil, forecast: [], textRev: 1)

        let fresh = try XCTUnwrap(JSONSerialization.jsonObject(
            with: snapshot.jsonData(now: updated.addingTimeInterval(29 * 60))) as? [String: Any])
        let stale = try XCTUnwrap(JSONSerialization.jsonObject(
            with: snapshot.jsonData(now: updated.addingTimeInterval(31 * 60))) as? [String: Any])

        XCTAssertTrue(fresh["temperature"] is NSNull)
        XCTAssertEqual(fresh["stale"] as? Bool, false)
        XCTAssertEqual(stale["stale"] as? Bool, true)
    }
}
