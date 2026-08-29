import Foundation

enum WeatherIcon: String, Codable {
    case clear
    case partlyCloudy
    case cloudy
    case overcast
    case fog
    case rain
    case showers
    case snow
    case thunderstorm
    case unknown
}

struct WeatherForecastDay: Codable, Equatable {
    let day: String
    let code: Int
    let high: Double?
    let low: Double?
}

struct WeatherCity: Codable, Equatable {
    let name: String
    let admin1: String
    let latitude: Double
    let longitude: Double
    let timezone: String
}

struct WeatherSnapshot: Codable, Equatable {
    let city: String
    let updatedAt: Date
    let weatherCode: Int
    let temperature: Double?
    let apparentTemperature: Double?
    let high: Double?
    let low: Double?
    let humidity: Int?
    let precipitationProbability: Int?
    let windSpeed: Double?
    let windDirectionDegrees: Int?
    let windDirection: String
    let aqi: Int?
    let forecast: [WeatherForecastDay]
    let textRev: Int

    func jsonData(now: Date = Date()) -> Data {
        func value(_ number: Any?) -> Any { number ?? NSNull() }
        let days: [[String: Any]] = forecast.map {
            ["day": $0.day, "code": $0.code, "high": value($0.high), "low": value($0.low)]
        }
        let object: [String: Any] = [
            "city": city,
            "updated_at": Int(updatedAt.timeIntervalSince1970),
            "weather_code": weatherCode,
            "temperature": value(temperature),
            "apparent_temperature": value(apparentTemperature),
            "high": value(high),
            "low": value(low),
            "humidity": value(humidity),
            "precipitation_probability": value(precipitationProbability),
            "wind_speed": value(windSpeed),
            "wind_direction_degrees": value(windDirectionDegrees),
            "wind_direction": windDirection,
            "aqi": value(aqi),
            "forecast": days,
            "text_rev": textRev,
            "stale": now.timeIntervalSince(updatedAt) > 30 * 60,
        ]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    }
}

final class WeatherMonitor {
    static func icon(for code: Int) -> WeatherIcon {
        switch code {
        case 0: return .clear
        case 1, 2: return .partlyCloudy
        case 3: return .overcast
        case 45, 48: return .fog
        case 51...67: return .rain
        case 80...82: return .showers
        case 71...77, 85, 86: return .snow
        case 95...99: return .thunderstorm
        default: return .unknown
        }
    }

    static func windDirection(degrees: Int) -> String {
        let normalized = ((degrees % 360) + 360) % 360
        let sectors = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
        return sectors[((normalized + 22) / 45) % sectors.count]
    }

    static func aqiGrade(_ aqi: Int) -> String {
        switch aqi {
        case ...50: return "优"
        case ...100: return "良"
        case ...150: return "轻度"
        case ...200: return "中度"
        case ...300: return "重度"
        default: return "严重"
        }
    }

    static func parseWeather(weatherData: Data, airData: Data, city: WeatherCity,
                             now: Date, textRev: Int) throws -> WeatherSnapshot {
        let weather = try JSONDecoder().decode(ForecastResponse.self, from: weatherData)
        let air = try JSONDecoder().decode(AirResponse.self, from: airData)
        let zone = TimeZone(identifier: city.timezone) ?? .current
        let localHour = localHourString(now, zone: zone)
        let remainingRain = zip(weather.hourly.time, weather.hourly.precipitationProbability)
            .filter { $0.0 >= localHour }
            .map(\.1)
            .compactMap { $0 }
            .max()
        let currentAQI = Array(zip(air.hourly.time, air.hourly.usAqi))
            .last(where: { $0.0 <= localHour })?.1
        let availableDays = [weather.daily.time.count, weather.daily.weatherCode.count,
                             weather.daily.temperatureMax.count, weather.daily.temperatureMin.count].min() ?? 0
        var forecast: [WeatherForecastDay] = []
        if availableDays > 1 {
            for index in 1..<min(availableDays, 4) {
                forecast.append(WeatherForecastDay(
                    day: forecastLabel(date: weather.daily.time[index], index: index, zone: zone),
                    code: weather.daily.weatherCode[index],
                    high: weather.daily.temperatureMax[index],
                    low: weather.daily.temperatureMin[index]))
            }
        }
        return WeatherSnapshot(
            city: city.name, updatedAt: now, weatherCode: weather.current.weatherCode,
            temperature: weather.current.temperature, apparentTemperature: weather.current.apparentTemperature,
            high: weather.daily.temperatureMax.first ?? nil, low: weather.daily.temperatureMin.first ?? nil,
            humidity: weather.current.humidity, precipitationProbability: remainingRain,
            windSpeed: weather.current.windSpeed, windDirectionDegrees: weather.current.windDirection,
            windDirection: weather.current.windDirection.map { windDirection(degrees: $0) } ?? "--",
            aqi: currentAQI ?? nil, forecast: forecast, textRev: textRev)
    }

    private static func localHourString(_ date: Date, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:00"
        return formatter.string(from: date)
    }

    private static func forecastLabel(date: String, index: Int, zone: TimeZone) -> String {
        if index == 1 { return "明天" }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = zone
        parser.dateFormat = "yyyy-MM-dd"
        guard let value = parser.date(from: date) else { return "--" }
        let labels = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return labels[Calendar(identifier: .gregorian).component(.weekday, from: value) - 1]
    }
}

private struct ForecastResponse: Decodable {
    struct Current: Decodable {
        let temperature: Double?
        let humidity: Int?
        let apparentTemperature: Double?
        let weatherCode: Int
        let windSpeed: Double?
        let windDirection: Int?

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case humidity = "relative_humidity_2m"
            case apparentTemperature = "apparent_temperature"
            case weatherCode = "weather_code"
            case windSpeed = "wind_speed_10m"
            case windDirection = "wind_direction_10m"
        }
    }
    struct Hourly: Decodable {
        let time: [String]
        let precipitationProbability: [Int?]
        enum CodingKeys: String, CodingKey {
            case time
            case precipitationProbability = "precipitation_probability"
        }
    }
    struct Daily: Decodable {
        let time: [String]
        let weatherCode: [Int]
        let temperatureMax: [Double?]
        let temperatureMin: [Double?]
        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
        }
    }
    let current: Current
    let hourly: Hourly
    let daily: Daily
}

private struct AirResponse: Decodable {
    struct Hourly: Decodable {
        let time: [String]
        let usAqi: [Int?]
        enum CodingKeys: String, CodingKey {
            case time
            case usAqi = "us_aqi"
        }
    }
    let hourly: Hourly
}
