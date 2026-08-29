import AppKit
import Foundation

protocol WeatherHTTPClient {
    func data(for url: URL) async throws -> Data
}

struct URLSessionWeatherClient: WeatherHTTPClient {
    func data(for url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

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
    static let defaultCity = WeatherCity(name: "成都", admin1: "四川", latitude: 30.66667,
                                         longitude: 104.06667, timezone: "Asia/Shanghai")

    private let client: WeatherHTTPClient
    private let cacheURL: URL
    private let nowProvider: () -> Date
    private let errorReporter: (Error) -> Void
    private let lock = NSLock()
    private var currentCity: WeatherCity
    private var storedSnapshot: WeatherSnapshot?
    private var storedText = Data([0])
    private var refreshInFlight = false
    private var timer: Timer?

    init(client: WeatherHTTPClient = URLSessionWeatherClient(), cacheURL: URL? = nil,
         now: @escaping () -> Date = Date.init,
         errorReporter: @escaping (Error) -> Void = {
             FileHandle.standardError.write(Data("[weather] refresh failed: \($0)\n".utf8))
         }) {
        self.client = client
        self.nowProvider = now
        self.errorReporter = errorReporter
        self.currentCity = Self.defaultCity
        self.cacheURL = cacheURL ?? Self.defaultCacheURL()
        if let data = try? Data(contentsOf: self.cacheURL),
           let cached = try? JSONDecoder().decode(WeatherSnapshot.self, from: data) {
            storedSnapshot = cached
            storedText = Self.renderTextStrips(Self.textStrings(for: cached))
        }
    }

    var snapshot: WeatherSnapshot? {
        withStateLock { storedSnapshot }
    }

    func jsonData() -> Data {
        withStateLock { storedSnapshot?.jsonData(now: nowProvider()) ?? Data("{\"available\":false}".utf8) }
    }

    func textRGB565() -> Data {
        withStateLock { storedText }
    }

    func start() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        guard let city = beginRefresh() else { return }
        defer { endRefresh() }
        guard let forecastURL = Self.forecastURL(for: city), let airURL = Self.airQualityURL(for: city) else { return }
        do {
            async let forecastRequest = client.data(for: forecastURL)
            async let airRequest = client.data(for: airURL)
            let (forecastData, airData) = try await (forecastRequest, airRequest)
            let oldRevision = snapshot?.textRev ?? 0
            var parsed = try Self.parseWeather(weatherData: forecastData, airData: airData,
                                               city: city, now: nowProvider(), textRev: oldRevision)
            let oldStrings = snapshot.map(Self.textStrings(for:)) ?? []
            let newStrings = Self.textStrings(for: parsed)
            if oldStrings != newStrings {
                parsed = WeatherSnapshot(city: parsed.city, updatedAt: parsed.updatedAt,
                    weatherCode: parsed.weatherCode, temperature: parsed.temperature,
                    apparentTemperature: parsed.apparentTemperature, high: parsed.high, low: parsed.low,
                    humidity: parsed.humidity, precipitationProbability: parsed.precipitationProbability,
                    windSpeed: parsed.windSpeed, windDirectionDegrees: parsed.windDirectionDegrees,
                    windDirection: parsed.windDirection, aqi: parsed.aqi, forecast: parsed.forecast,
                    textRev: oldRevision + 1)
            }
            let rendered = Self.renderTextStrips(newStrings)
            withStateLock {
                storedSnapshot = parsed
                storedText = rendered
            }
            persist(parsed)
        } catch {
            errorReporter(error)
        }
    }

    private func withStateLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }

    private func beginRefresh() -> WeatherCity? {
        withStateLock {
            guard !refreshInFlight else { return nil }
            refreshInFlight = true
            return currentCity
        }
    }

    private func endRefresh() {
        withStateLock { refreshInFlight = false }
    }

    private func persist(_ snapshot: WeatherSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let directory = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = cacheURL.appendingPathExtension("tmp")
        do {
            try data.write(to: temporary, options: .atomic)
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                _ = try FileManager.default.replaceItemAt(cacheURL, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: cacheURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
        }
    }

    private static func defaultCacheURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("AIClockBridge/weather-cache.json")
    }

    private static func textStrings(for snapshot: WeatherSnapshot) -> [String] {
        let condition = conditionText(for: snapshot.weatherCode)
        let grade = snapshot.aqi.map(aqiGrade) ?? "--"
        return [snapshot.city, condition, snapshot.windDirection, grade]
            + snapshot.forecast.map(\.day)
            + Array(repeating: "", count: max(0, 3 - snapshot.forecast.count))
    }

    static func conditionText(for code: Int) -> String {
        switch icon(for: code) {
        case .clear: return "晴"
        case .partlyCloudy: return "少云"
        case .cloudy: return "多云"
        case .overcast: return "阴"
        case .fog: return "雾"
        case .rain: return "雨"
        case .showers: return "阵雨"
        case .snow: return "雪"
        case .thunderstorm: return "雷雨"
        case .unknown: return "未知"
        }
    }

    static func forecastURL(for city: WeatherCity) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(city.latitude)),
            URLQueryItem(name: "longitude", value: String(city.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m"),
            URLQueryItem(name: "hourly", value: "precipitation_probability"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "forecast_days", value: "4"),
            URLQueryItem(name: "timezone", value: city.timezone),
        ]
        return components?.url
    }

    static func airQualityURL(for city: WeatherCity) -> URL? {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(city.latitude)),
            URLQueryItem(name: "longitude", value: String(city.longitude)),
            URLQueryItem(name: "hourly", value: "us_aqi"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timezone", value: city.timezone),
        ]
        return components?.url
    }

    static func renderTextStrips(_ source: [String]) -> Data {
        let width = 232, height = 16, count = 7
        var output = Data([UInt8(count)])
        for index in 0..<count {
            let text = index < source.count ? source[index] : ""
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                output.append(Data(count: width * height * 2))
                continue
            }
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            (text as NSString).draw(with: NSRect(x: 0, y: 1, width: width, height: height - 1), attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
            ])
            NSGraphicsContext.restoreGraphicsState()
            guard let rendered = context.data else {
                output.append(Data(count: width * height * 2))
                continue
            }
            let pixels = rendered.bindMemory(to: UInt8.self, capacity: width * height * 4)
            for pixel in 0..<(width * height) {
                let offset = pixel * 4
                let value = (UInt16(pixels[offset] & 0xF8) << 8)
                    | (UInt16(pixels[offset + 1] & 0xFC) << 3)
                    | UInt16(pixels[offset + 2] >> 3)
                output.append(UInt8(value >> 8))
                output.append(UInt8(value & 0xFF))
            }
        }
        return output
    }

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
