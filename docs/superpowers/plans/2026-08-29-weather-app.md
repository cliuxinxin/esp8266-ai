# Weather App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an enhanced Chengdu weather page with cached Open-Meteo data, manual display mode, automatic low-priority rotation, and matching macOS, Windows, and ESP8266 views.

**Architecture:** Desktop bridge monitors own all public API access, persistence, Chinese text rendering, and normalized weather JSON. ESP8266 polls compact `/weather` and `/weather/text.raw` resources, renders fixed pixel icons and a 240×240 card layout, and inserts weather below approvals, active agents, and music in AUTO priority. macOS is completed first with firmware; Windows then ports the same wire contract.

**Tech Stack:** Swift 5.9/AppKit/Foundation, XCTest, C#/.NET 8 WinForms/System.Text.Json, ESP8266 Arduino/C++, ArduinoJson, TFT_eSPI, PlatformIO.

**Spec:** `docs/superpowers/specs/2026-08-29-weather-app-design.md`

**Scope update (2026-08-29):** The user explicitly deferred Windows support. Tasks 6 and 7 are not part of this execution; the release gate covers macOS plus ESP8266 only.

## Global Constraints

- Default city is 成都 at latitude `30.66667`, longitude `104.06667`, timezone `Asia/Shanghai`.
- Desktop refresh interval is 10 minutes; data becomes stale after 30 minutes.
- AUTO weather interval is 15 minutes and each weather window lasts 10 seconds.
- AUTO priority is approval, active Claude/Codex, music, weather, then idle Claude/Codex rotation.
- `/weather/text.raw` is `[1B count][7 × 232 × 16 RGB565 big-endian pixels]` in city, condition, wind, AQI grade, and three forecast-label order.
- ESP8266 keeps at most three forecast days and reuses row buffers; it must not allocate a full-screen or full-text-strip frame buffer.
- Missing optional numeric values are JSON `null` and render as `--`, never zero.
- Weather icons are limited to clear, partly cloudy, cloudy, overcast, fog, rain, showers, snow, thunderstorm, and unknown.
- Public weather requests remain in desktop bridges; firmware never calls Open-Meteo directly.
- macOS implementation uses only system frameworks; Windows uses the existing .NET 8 project dependencies.

---

### Task 1: macOS weather normalization and mappings

**Files:**
- Create: `mac-app/Sources/AIClockBridge/WeatherMonitor.swift`
- Create: `mac-app/Tests/AIClockBridgeTests/WeatherMonitorTests.swift`

**Interfaces:**
- Produces: `WeatherIcon`, `WeatherForecastDay`, `WeatherSnapshot`, `WeatherMonitor.icon(for:)`, `WeatherMonitor.windDirection(degrees:)`, `WeatherMonitor.aqiGrade(_:)`, and `WeatherMonitor.parseWeather(weatherData:airData:city:now:)`.
- `WeatherSnapshot.jsonData(now:) -> Data` is the exact `/weather` payload consumed by Tasks 2–7.

- [ ] **Step 1: Write mapping tests**

```swift
import XCTest
@testable import AIClockBridge

final class WeatherMonitorTests: XCTestCase {
    func testWeatherCodeMapping() {
        XCTAssertEqual(WeatherMonitor.icon(for: 0), .clear)
        XCTAssertEqual(WeatherMonitor.icon(for: 3), .overcast)
        XCTAssertEqual(WeatherMonitor.icon(for: 45), .fog)
        XCTAssertEqual(WeatherMonitor.icon(for: 61), .rain)
        XCTAssertEqual(WeatherMonitor.icon(for: 80), .showers)
        XCTAssertEqual(WeatherMonitor.icon(for: 71), .snow)
        XCTAssertEqual(WeatherMonitor.icon(for: 95), .thunderstorm)
        XCTAssertEqual(WeatherMonitor.icon(for: 999), .unknown)
    }

    func testWindAndAQIBoundaries() {
        XCTAssertEqual(WeatherMonitor.windDirection(degrees: 0), "北")
        XCTAssertEqual(WeatherMonitor.windDirection(degrees: 225), "西南")
        XCTAssertEqual(WeatherMonitor.windDirection(degrees: 359), "北")
        XCTAssertEqual(WeatherMonitor.aqiGrade(50), "优")
        XCTAssertEqual(WeatherMonitor.aqiGrade(51), "良")
        XCTAssertEqual(WeatherMonitor.aqiGrade(301), "严重")
    }
}
```

- [ ] **Step 2: Run the tests and verify failure**

Run: `cd mac-app && swift test --filter WeatherMonitorTests`

Expected: compilation fails because `WeatherMonitor` and `WeatherIcon` do not exist.

- [ ] **Step 3: Implement fixed mappings and value types**

```swift
enum WeatherIcon: String, Codable {
    case clear, partlyCloudy, cloudy, overcast, fog, rain, showers, snow, thunderstorm, unknown
}

struct WeatherForecastDay: Codable, Equatable {
    let day: String
    let code: Int
    let high: Double?
    let low: Double?
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
}
```

Implement WMO code groups exactly as asserted, eight 45° wind sectors using `(degrees + 22) / 45 % 8`, and US AQI thresholds `0...50`, `51...100`, `101...150`, `151...200`, `201...300`, `301+`.

- [ ] **Step 4: Add fixture parsing tests**

Use inline JSON fixtures containing `current`, `hourly`, and `daily` arrays. Assert current temperature/humidity/wind, the maximum remaining-hour precipitation probability, daily high/low, three forecast days excluding today, AQI, local weekday labels, `null` preservation, and `stale == false` at 29 minutes / `true` at 31 minutes in serialized JSON.

- [ ] **Step 5: Implement parsing and JSON serialization**

Decode only required keys with private `Decodable` DTOs. Match hourly timestamps against the supplied `now` in the configured timezone, cap forecast with `Array(days.dropFirst().prefix(3))`, and serialize snake_case keys with `JSONSerialization` so `nil` becomes `NSNull()`.

- [ ] **Step 6: Run the focused and full Mac tests**

Run: `cd mac-app && swift test --filter WeatherMonitorTests && swift test`

Expected: all tests pass.

- [ ] **Step 7: Commit the normalization layer**

```bash
git add mac-app/Sources/AIClockBridge/WeatherMonitor.swift mac-app/Tests/AIClockBridgeTests/WeatherMonitorTests.swift
git commit -m "feat(mac): add weather data model"
```

### Task 2: macOS fetching, persistence, and bridge routes

**Files:**
- Modify: `mac-app/Sources/AIClockBridge/WeatherMonitor.swift`
- Modify: `mac-app/Sources/AIClockBridge/main.swift:39-90`
- Modify: `mac-app/Tests/AIClockBridgeTests/WeatherMonitorTests.swift`

**Interfaces:**
- Consumes: Task 1 `WeatherSnapshot` and parser.
- Produces: `WeatherMonitor.start()`, `snapshot`, `jsonData()`, `textRGB565()`, and `setCity(_ city: WeatherCity, completion:)`.
- Produces HTTP routes `GET /weather` and `GET /weather/text.raw`.

- [ ] **Step 1: Add injectable client and cache tests**

Define in the test file:

```swift
final class StubWeatherClient: WeatherHTTPClient {
    var responses: [URL: Result<Data, Error>] = [:]
    func data(for url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        completion(responses[url] ?? .failure(URLError(.badURL)))
    }
}
```

Test that one refresh merges weather and AQI, overlapping `refresh()` calls produce one client request pair, a failed refresh retains the prior snapshot, a 31-minute restored cache is stale, and a city switch does not relabel the old snapshot before the new city succeeds.

- [ ] **Step 2: Run focused tests and verify failure**

Run: `cd mac-app && swift test --filter WeatherMonitorTests`

Expected: compilation fails because `WeatherHTTPClient`, refresh, persistence, and text accessors are absent.

- [ ] **Step 3: Implement request and persistence boundaries**

```swift
protocol WeatherHTTPClient {
    func data(for url: URL, completion: @escaping (Result<Data, Error>) -> Void)
}

struct WeatherCity: Codable, Equatable {
    let name: String
    let admin1: String
    let latitude: Double
    let longitude: Double
    let timezone: String
}
```

Use a serial state queue, `refreshInFlight`, a 600-second timer, `URLSession` with 8-second timeout, and a cache file under Application Support. Write cache data to a sibling temporary file, then use `FileManager.replaceItemAt` or move when the destination does not exist. Default `WeatherCity` is 成都/四川 with the global coordinates and timezone.

- [ ] **Step 4: Implement exact Open-Meteo requests**

Forecast query includes `current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m`, `hourly=precipitation_probability`, `daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max`, `forecast_days=4`, and `timezone=<city timezone>`. Air query includes `hourly=us_aqi` with the same coordinates and timezone. Percent-encode all query items with `URLComponents`.

- [ ] **Step 5: Implement seven rendered text strips**

Render seven `232×16` black-background strips with `NSGraphicsContext` and system font at 12 points. Emit byte `7`, then RGB565 big-endian pixels in city, condition, wind, AQI grade, and three label order. Increment `textRev` only when those seven source strings change.

- [ ] **Step 6: Register and identify weather routes**

In `main.swift`, construct and start `WeatherMonitor`, add `"/weather": { weatherMonitor.jsonData() }`, add `"/weather/text.raw": { weatherMonitor.textRGB565() }`, pass it to later UI constructors, and include `/weather` in passive device-discovery route checks.

- [ ] **Step 7: Run tests and manually smoke-test JSON**

Run: `cd mac-app && swift test && swift build`

Then run the bridge and verify: `curl -s http://localhost:8765/weather | python3 -m json.tool` and `curl -s http://localhost:8765/weather/text.raw | wc -c`.

Expected binary length: `1 + 7 * 232 * 16 * 2 = 51969` bytes.

- [ ] **Step 8: Commit bridge weather service**

```bash
git add mac-app/Sources/AIClockBridge/WeatherMonitor.swift mac-app/Sources/AIClockBridge/main.swift mac-app/Tests/AIClockBridgeTests/WeatherMonitorTests.swift
git commit -m "feat(mac): serve cached weather data"
```

### Task 3: Firmware weather parsing and display mode contract

**Files:**
- Modify: `firmware/include/config.h`
- Modify: `firmware/src/main.cpp:70-150,1100-1460,1520-1830,2130-2270`
- Create: `firmware/include/weather_logic.h`
- Create: `firmware/include/img/weather_icons.h`
- Create: `firmware/test/test_weather/test_main.cpp`

**Interfaces:**
- Consumes: Task 2 `/weather` and `/weather/text.raw` contracts.
- Produces: `MODE_WEATHER`, `WeatherState`, `weatherIconForCode(int)`, `parseWeatherPayload(const String&)`, `pollWeather()`, `drawWeatherScreen()`, and device API mode string `weather`.

- [ ] **Step 1: Extract pure weather mappings and write native tests**

Add PlatformIO native tests that assert WMO code mapping, integer rounding, missing-value flags, three-day truncation, and rejection of a fourth forecast row. Put the shared enums, value structs, and mapping functions in `firmware/include/weather_logic.h` without Arduino networking dependencies; include that header from both `main.cpp` and the native test.

```cpp
TEST_CASE("weather codes map to fixed icons") {
  CHECK(weatherIconForCode(0) == WEATHER_CLEAR);
  CHECK(weatherIconForCode(61) == WEATHER_RAIN);
  CHECK(weatherIconForCode(999) == WEATHER_UNKNOWN);
}
```

- [ ] **Step 2: Run native test and verify failure**

Run: `cd firmware && pio test -e native -f test_weather`

Expected: compilation fails because weather types and mappings do not exist. If the current PlatformIO configuration has no native environment, add `[env:native] platform = native` with ArduinoJson available only to the test build.

- [ ] **Step 3: Add constants, state, and pure mappings**

In `config.h` define `WEATHER_POLL_INTERVAL_MS 600000UL`, `WEATHER_STALE_MS 1800000UL`, `WEATHER_AUTO_INTERVAL_MS 900000UL`, `WEATHER_AUTO_DURATION_MS 10000UL`, `WEATHER_TEXT_W 232`, `WEATHER_TEXT_H 16`, and `WEATHER_TEXT_COUNT 7`. Define `WeatherState` with validity flags instead of numeric sentinels for nullable fields and a fixed `WeatherDay forecast[3]`.

- [ ] **Step 4: Parse bounded JSON and expose weather mode**

Parse with a fixed-capacity `StaticJsonDocument` sized from the measured payload plus 25% margin. Reject parse errors, missing city/code/timestamp, and oversized forecast arrays; keep the prior state on rejection. Add `weather` to serial mode parsing, `displayModeName`, `/api/display`, and `/api/info`.

- [ ] **Step 5: Add pixel icons and card-layout renderer**

Create PROGMEM 1-bit weather icon bitmaps no larger than `48×48`. Implement the approved C layout with top text, central temperature/icon, two-column metrics, and three forecast columns. Use `rowBuf` for text downloads and local clearing rectangles for changed values.

- [ ] **Step 6: Implement polling and text revision behavior**

Poll `/weather` every 10 minutes in weather mode and after bridge discovery. Download `/weather/text.raw` only when `text_rev` changes, validate exact length `51969`, and draw its seven strips one row at a time. Failed JSON or binary responses leave prior state/text intact.

- [ ] **Step 7: Run native tests and firmware build**

Run: `cd firmware && pio test -e native -f test_weather && pio run`

Expected: tests pass and firmware builds without overflow. Record program/RAM percentages and compare with the baseline printed by the current build.

- [ ] **Step 8: Commit firmware weather mode**

```bash
git add firmware/platformio.ini firmware/include/config.h firmware/include/weather_logic.h firmware/include/img/weather_icons.h firmware/src/main.cpp firmware/test/test_weather/test_main.cpp
git commit -m "feat(firmware): add weather display mode"
```

### Task 4: Firmware AUTO rotation and priority

**Files:**
- Modify: `firmware/src/main.cpp:1524-1580,2210-2270`
- Modify: `firmware/test/test_weather/test_main.cpp`

**Interfaces:**
- Consumes: Task 3 `MODE_WEATHER` and weather validity.
- Produces: pure `chooseAutoMode(const AutoModeInputs&)` and timer state `weatherAutoDueMs`, `weatherAutoUntilMs`.

- [ ] **Step 1: Write priority and timer tests**

Cover approval over every mode, working agent over music/weather, music over weather, weather over idle, no weather before the first 15-minute period, a 10-second window, invalid-weather suppression, immediate interruption, and next due time based on the interrupted window's original end.

```cpp
CHECK(chooseAutoMode({.approval=true, .music=true, .weatherWindow=true}) == MODE_AUTO);
CHECK(chooseAutoMode({.working=true, .music=true, .weatherWindow=true}) == MODE_AUTO);
CHECK(chooseAutoMode({.music=true, .weatherWindow=true}) == MODE_MUSIC);
CHECK(chooseAutoMode({.weatherValid=true, .weatherWindow=true}) == MODE_WEATHER);
```

- [ ] **Step 2: Run native tests and verify failure**

Run: `cd firmware && pio test -e native -f test_weather`

Expected: compilation fails because AUTO selection inputs and scheduler are absent.

- [ ] **Step 3: Implement AUTO scheduler and selection**

Initialize first due time only after valid weather exists. Set `weatherAutoUntilMs = due + 10000` and next due to `weatherAutoUntilMs + 900000`. Use wrap-safe signed subtraction for `millis()`. Preserve pinned-mode behavior by running this logic only when `displayMode == MODE_AUTO`.

- [ ] **Step 4: Integrate transitions and polling**

Add weather to effective-mode transition clearing, main-loop draw dispatch, HTTP polling, and wired-mode exclusions. Ensure approval and agent activity are checked before music and weather on every loop.

- [ ] **Step 5: Verify tests and build**

Run: `cd firmware && pio test -e native -f test_weather && pio run`

Expected: all priority tests pass and firmware builds.

- [ ] **Step 6: Commit AUTO weather rotation**

```bash
git add firmware/src/main.cpp firmware/test/test_weather/test_main.cpp
git commit -m "feat(firmware): rotate weather in auto mode"
```

### Task 5: macOS menu, city picker, and mirror

**Files:**
- Modify: `mac-app/Sources/AIClockBridge/MenuBarController.swift:20-115,160-265`
- Modify: `mac-app/Sources/AIClockBridge/MirrorPopover.swift`
- Modify: `mac-app/Sources/AIClockBridge/DeviceClient.swift:1-80`
- Modify: `mac-app/Sources/AIClockBridge/main.swift`
- Modify: `mac-app/Tests/AIClockBridgeTests/WeatherMonitorTests.swift`

**Interfaces:**
- Consumes: Task 2 `WeatherMonitor`; Task 3 device mode `weather`.
- Produces: weather display menu item, `WeatherMonitor.searchCities(query:completion:)`, persisted pending-city selection, and `MirrorView.weatherSnapshotProvider`.

- [ ] **Step 1: Add geocoding decode tests**

Provide an inline geocoding fixture with the real Chengdu result and two namesakes. Assert `WeatherMonitor.parseCities(data:)` keeps name/admin/coordinates/timezone and that the result label is `成都 · 四川`.

- [ ] **Step 2: Run tests and verify failure**

Run: `cd mac-app && swift test --filter WeatherMonitorTests`

Expected: failure because geocoding parser/search does not exist.

- [ ] **Step 3: Implement city search**

Request `https://geocoding-api.open-meteo.com/v1/search` using `name`, `count=10`, `language=zh`, and `format=json`. Return results on the main queue. Empty, failed, or malformed responses return a localized error and never change stored city.

- [ ] **Step 4: Add menu and city-selection sheet**

Add `("天气", "weather")` to the display menu. Add “设置天气城市…” that opens an `NSAlert` with search input, then a second chooser containing `城市 · 省份`; choosing a result calls `setCity`. Pass `weatherMonitor` through `main.swift` into `MenuBarController` and `MirrorPopoverController`.

- [ ] **Step 5: Draw matching mirror scene**

Extend device info parsing so `effective == "weather"` selects weather rendering. Draw the same four regions and values as firmware with AppKit pixel-aligned rectangles and matching colors; use native Chinese text in the mirror and the same code-to-icon mapping.

- [ ] **Step 6: Run Mac verification**

Run: `cd mac-app && swift test && swift build`

Manual checks: select weather, search 成都, choose 四川 result, confirm `/weather` retains old city until new data succeeds, and confirm mirror follows device `effective=weather`.

- [ ] **Step 7: Commit Mac UI**

```bash
git add mac-app/Sources/AIClockBridge/MenuBarController.swift mac-app/Sources/AIClockBridge/MirrorPopover.swift mac-app/Sources/AIClockBridge/DeviceClient.swift mac-app/Sources/AIClockBridge/main.swift mac-app/Tests/AIClockBridgeTests/WeatherMonitorTests.swift
git commit -m "feat(mac): add weather controls and mirror"
```

### Task 6: Windows weather monitor and bridge routes

**Files:**
- Create: `windows-app/AIClockBridge/WeatherMonitor.cs`
- Create: `windows-app/AIClockBridge.Tests/WeatherMonitorTests.cs`
- Create: `windows-app/AIClockBridge.Tests/AIClockBridge.Tests.csproj`
- Modify: `windows-app/AIClockBridge/Program.cs:25-105`
- Modify: `windows-app/AIClockBridge/Settings.cs`

**Interfaces:**
- Consumes: exact Task 2 wire schema and text-strip dimensions.
- Produces: C# `WeatherMonitor.Start()`, `JsonData`, `TextRgb565`, `SearchCitiesAsync`, and `SetCityAsync`.

- [ ] **Step 1: Create xUnit test project and failing parity tests**

Reference the main project and add tests for the same WMO, wind, AQI, fixture parsing, staleness, cache retention, city-switch, and exact 51,969-byte text payload cases as Tasks 1–2.

- [ ] **Step 2: Run tests and verify failure**

Run: `dotnet test windows-app/AIClockBridge.Tests/AIClockBridge.Tests.csproj`

Expected: compilation fails because Windows `WeatherMonitor` does not exist.

- [ ] **Step 3: Implement the Windows monitor**

Use `HttpClient` with an 8-second timeout, `System.Text.Json`, a `System.Threading.Timer`, and a lock around snapshot/text state. Use `Settings` keys prefixed `weather_`; store the cached snapshot as JSON. Use `System.Drawing` to render the seven black-background 232×16 strips and convert BGRA pixels to RGB565 big-endian.

- [ ] **Step 4: Register routes and passive discovery**

Construct/start `WeatherMonitor` in `Program.cs`; add `/weather`, `/weather/text.raw`, and `/weather` to passive discovery checks.

- [ ] **Step 5: Verify tests and application build**

Run: `dotnet test windows-app/AIClockBridge.Tests/AIClockBridge.Tests.csproj && dotnet build windows-app/AIClockBridge/AIClockBridge.csproj`

Expected: all tests pass and the WinForms application builds.

- [ ] **Step 6: Commit Windows bridge support**

```bash
git add windows-app/AIClockBridge/WeatherMonitor.cs windows-app/AIClockBridge/Program.cs windows-app/AIClockBridge/Settings.cs windows-app/AIClockBridge.Tests
git commit -m "feat(windows): serve cached weather data"
```

### Task 7: Windows tray controls and mirror

**Files:**
- Modify: `windows-app/AIClockBridge/TrayAppContext.cs:20-120,180-280`
- Modify: `windows-app/AIClockBridge/MirrorForm.cs`
- Modify: `windows-app/AIClockBridge/DeviceClient.cs`
- Modify: `windows-app/AIClockBridge/Program.cs`

**Interfaces:**
- Consumes: Task 6 `WeatherMonitor`; Task 3 device mode `weather`.
- Produces Windows weather menu, city chooser, and mirror scene matching macOS and firmware.

- [ ] **Step 1: Add weather dependencies and menu mode**

Pass `WeatherMonitor` into `TrayAppContext` and `MirrorForm`. Add `("天气", "weather")` to the display menu and map device `Mode`/`Effective` values without falling back to auto.

- [ ] **Step 2: Implement city search dialog**

Use a small WinForms dialog with a text box, Search button, result list labeled `城市 · 省份`, and Confirm button disabled until selection. Search asynchronously; surface failures without overwriting the current city.

- [ ] **Step 3: Implement mirror weather scene**

Draw the fixed four-region C layout with `System.Drawing`, native Chinese text, shared weather icon mapping, nullable values as `--`, and yellow stale indicator.

- [ ] **Step 4: Build and manually verify**

Run: `dotnet test windows-app/AIClockBridge.Tests/AIClockBridge.Tests.csproj && dotnet build windows-app/AIClockBridge/AIClockBridge.csproj`

Manual checks on Windows: city search, fixed weather mode, AUTO effective weather following the device, stale rendering, and matching values with `/weather`.

- [ ] **Step 5: Commit Windows UI**

```bash
git add windows-app/AIClockBridge/TrayAppContext.cs windows-app/AIClockBridge/MirrorForm.cs windows-app/AIClockBridge/DeviceClient.cs windows-app/AIClockBridge/Program.cs
git commit -m "feat(windows): add weather controls and mirror"
```

### Task 8: Documentation and end-to-end verification

**Files:**
- Modify: `README.md`
- Modify: `README.en.md`
- Modify: `docs/DEVELOPMENT.md`
- Modify: `firmware/include/config.h` for final version number only

**Interfaces:**
- Consumes: all prior tasks.
- Produces documented `/weather`, `/weather/text.raw`, weather mode, city setup, AUTO behavior, and measured resource results.

- [ ] **Step 1: Update user documentation**

Add enhanced weather to feature lists, describe default 成都 and “设置天气城市…”, document fixed/manual and AUTO behavior, and add troubleshooting for stale/unavailable weather. Keep Chinese and English README content equivalent.

- [ ] **Step 2: Update developer documentation**

Document both endpoints including nullable semantics and exact raw size/order, Open-Meteo ownership, 10-minute/30-minute/15-minute/10-second timings, priority order, code/icon mapping, and cache behavior.

- [ ] **Step 3: Bump firmware version**

Change `FW_VERSION` from `0.4.11` to `0.4.12` after all behavior is finalized.

- [ ] **Step 4: Run complete automated verification**

```bash
cd mac-app && swift test && swift build
cd ../firmware && pio test -e native -f test_weather && pio run
cd .. && dotnet test windows-app/AIClockBridge.Tests/AIClockBridge.Tests.csproj
dotnet build windows-app/AIClockBridge/AIClockBridge.csproj
git diff --check
```

Expected: every command exits zero. Record firmware Flash/RAM percentages in `docs/DEVELOPMENT.md`.

- [ ] **Step 5: Perform end-to-end checks**

Run the Mac bridge, inspect `/weather`, confirm binary length 51,969 bytes, pin the device to weather, observe the mirror, return to AUTO, and simulate approval/working/music transitions. Disconnect public internet, confirm cached display remains and becomes stale after the threshold using an injected clock or test-only fixture rather than waiting 30 minutes.

- [ ] **Step 6: Run a bounded soak test**

Run bridge and device for 24 hours while logging ESP free heap before/after each weather refresh. The release gate is no monotonic heap decline, no overlapping desktop refresh, no stuck AUTO window, and no accumulated HTTP failure. Record start/end heap, minimum heap, refresh count, and mode-transition count in `docs/DEVELOPMENT.md`.

- [ ] **Step 7: Commit documentation and version**

```bash
git add README.md README.en.md docs/DEVELOPMENT.md firmware/include/config.h
git commit -m "docs: document weather display"
```

- [ ] **Step 8: Review final diff**

Run `git status --short`, `git log --oneline -10`, and `git diff HEAD~8..HEAD --stat`. Confirm only weather-related files and the previously approved design/plan are present; do not stage or remove `.superpowers/` visual-companion state.
