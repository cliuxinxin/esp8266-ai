# Configurable Auto Display and Quotes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-source automatic-display controls and a cached bilingual online quotes screen to the macOS bridge and ESP8266 firmware.

**Architecture:** The Mac owns and persists `AutoDisplaySettings`, fetches and rasterizes quotes, and publishes both through the existing bridge. The ESP8266 keeps the last received configuration in memory, runs a generic event-priority/fair-scheduled-page selector, and renders quote text using a fixed RGB565 layer supplied by the Mac.

**Tech Stack:** Swift 5.9, AppKit, Foundation/URLSession, XCTest, C++17 native logic tests, Arduino/ESP8266, ArduinoJson, TFT_eSPI, PlatformIO.

**Spec:** `docs/superpowers/specs/2026-08-29-auto-display-quotes-design.md`

## Global Constraints

- Scope is macOS plus ESP8266; do not modify `windows-app/`.
- Claude defaults off; Codex, approvals, music, weather, and quotes default on; stocks and net default off.
- Scheduled intervals clamp to 1–240 minutes and durations clamp to 5–60 seconds.
- Fixed modes remain available even when their automatic participation is disabled.
- Quote language alternates between Chinese and English when both services are healthy.
- Chinese uses Hitokoto; English uses ZenQuotes; neither API is called by the ESP8266.
- No new third-party Mac package dependencies.
- Preserve compatibility with a bridge payload that has no `auto_display` object.

---

### Task 1: Auto Display Settings Model and Persistence

**Files:**
- Create: `mac-app/Sources/AIClockBridge/AutoDisplaySettings.swift`
- Create: `mac-app/Tests/AIClockBridgeTests/AutoDisplaySettingsTests.swift`

**Interfaces:**
- Produces: `enum AutoDisplayItemID: String, Codable, CaseIterable`
- Produces: `struct ScheduledDisplaySetting: Codable, Equatable`
- Produces: `struct AutoDisplayConfiguration: Codable, Equatable`
- Produces: `final class AutoDisplaySettingsStore` with `configuration`, `save(_:)`, `jsonObject()`, and monotonic `revision`

- [ ] **Step 1: Write failing tests for defaults and clamping**

```swift
func testDefaultsMatchProductDecision() {
    let c = AutoDisplayConfiguration.defaults
    XCTAssertFalse(c.events[.claude]!)
    XCTAssertTrue(c.events[.codex]!)
    XCTAssertTrue(c.events[.approval]!)
    XCTAssertTrue(c.events[.music]!)
    XCTAssertEqual(c.scheduled[.weather], .init(enabled: true, intervalSeconds: 900, durationSeconds: 10))
    XCTAssertEqual(c.scheduled[.quote], .init(enabled: true, intervalSeconds: 1800, durationSeconds: 12))
    XCTAssertEqual(c.scheduled[.stock]?.enabled, false)
    XCTAssertEqual(c.scheduled[.net]?.enabled, false)
}

func testNormalizeClampsScheduledValues() {
    var c = AutoDisplayConfiguration.defaults
    c.scheduled[.quote] = .init(enabled: true, intervalSeconds: 1, durationSeconds: 999)
    c.normalize()
    XCTAssertEqual(c.scheduled[.quote]?.intervalSeconds, 60)
    XCTAssertEqual(c.scheduled[.quote]?.durationSeconds, 60)
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run: `cd mac-app && swift test --filter AutoDisplaySettingsTests`

Expected: FAIL because the settings types do not exist.

- [ ] **Step 3: Implement the value types and normalization**

```swift
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

    mutating func normalize() {
        for key in [AutoDisplayItemID.weather, .quote, .stock, .net] {
            guard var item = scheduled[key] else { continue }
            item.intervalSeconds = min(14_400, max(60, item.intervalSeconds))
            item.durationSeconds = min(60, max(5, item.durationSeconds))
            scheduled[key] = item
        }
    }
}
```

Add the exact defaults from the global constraints.

- [ ] **Step 4: Write failing persistence and revision tests**

```swift
func testStorePersistsNormalizedConfigurationAndIncrementsRevision() throws {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = AutoDisplaySettingsStore(defaults: defaults)
    var c = store.configuration
    c.events[.claude] = true
    let oldRevision = store.revision
    store.save(c)
    XCTAssertTrue(AutoDisplaySettingsStore(defaults: defaults).configuration.events[.claude]!)
    XCTAssertGreaterThan(store.revision, oldRevision)
    XCTAssertEqual(store.jsonObject()["revision"] as? Int, store.revision)
}
```

- [ ] **Step 5: Implement persistence and JSON serialization**

Use one `Codable` data blob under `auto_display_configuration_v1` and an integer under `auto_display_revision`. When decoding fails, return `.defaults`; `save(_:)` normalizes before encoding and increments the revision.

- [ ] **Step 6: Run tests and commit**

Run: `cd mac-app && swift test --filter AutoDisplaySettingsTests`

Expected: PASS.

```bash
git add mac-app/Sources/AIClockBridge/AutoDisplaySettings.swift mac-app/Tests/AIClockBridgeTests/AutoDisplaySettingsTests.swift
git commit -m "feat(mac): add automatic display settings"
```

---

### Task 2: Bilingual Quote Fetching, Filtering, Cache, and Rasterization

**Files:**
- Create: `mac-app/Sources/AIClockBridge/QuoteMonitor.swift`
- Create: `mac-app/Tests/AIClockBridgeTests/QuoteMonitorTests.swift`

**Interfaces:**
- Produces: `struct QuoteSnapshot: Codable, Equatable`
- Produces: `protocol QuoteHTTPClient { func data(from url: URL) async throws -> Data }`
- Produces: `final class QuoteMonitor` with `snapshot`, `start()`, `refresh(force:)`, `jsonData()`, and `textRGB565()`
- Consumes: the AppKit RGB565 text rendering pattern in `WeatherMonitor.swift`

- [ ] **Step 1: Write failing response parsing tests**

```swift
func testParsesHitokotoAndZenQuotes() throws {
    let zh = Data(#"{"hitokoto":"知者不惑。","from":"论语","from_who":"孔子"}"#.utf8)
    let en = Data(#"[{"q":"Stay hungry, stay foolish.","a":"Steve Jobs"}]"#.utf8)
    XCTAssertEqual(try QuoteMonitor.parseHitokoto(zh).author, "孔子")
    XCTAssertEqual(try QuoteMonitor.parseZenQuotes(en).text, "Stay hungry, stay foolish.")
}

func testAuthorFallsBackToSourceThenAnonymous() throws {
    let sourceOnly = Data(#"{"hitokoto":"山高水长","from":"古语","from_who":null}"#.utf8)
    XCTAssertEqual(try QuoteMonitor.parseHitokoto(sourceOnly).author, "古语")
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run: `cd mac-app && swift test --filter QuoteMonitorTests`

Expected: FAIL because `QuoteMonitor` does not exist.

- [ ] **Step 3: Implement normalized parsing and validation**

```swift
struct QuoteSnapshot: Codable, Equatable {
    let text: String
    let author: String
    let language: String
    let updatedAt: Date
    let textRev: Int
}

static func isDisplayable(_ quote: QuoteSnapshot) -> Bool {
    let count = quote.text.count
    return !quote.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && count <= (quote.language == "zh" ? 80 : 180)
}
```

Parse `from_who`, then `from`, then `佚名` for Hitokoto. Parse `a`, then `Anonymous` for ZenQuotes.

- [ ] **Step 4: Write failing tests for alternation, duplicate rejection, and fallback cache**

Create a stub client keyed by host. Assert a successful Chinese refresh makes the next requested service English; repeated text is rejected; after a later network failure `snapshot` remains the previous successful quote and serialized JSON reports `stale: true` only after the configured stale threshold.

- [ ] **Step 5: Implement refresh orchestration and persistent cache**

Use `https://v1.hitokoto.cn/?encode=json&c=d&c=k` for Chinese and `https://zenquotes.io/api/random` for English. Use an 8-second `URLRequest` timeout, at most three content attempts, a bounded recent-text set of 20 items, and cache JSON at `Application Support/AIClockBridge/quote-cache.json`. Serialize keys `text`, `author`, `language`, `updated_at`, `text_rev`, and `stale`.

- [ ] **Step 6: Write and pass the fixed-wire-size raster test**

```swift
func testTextRGB565HasFixed240SquareWireSize() async throws {
    // Seed the monitor with one successful stub response.
    await monitor.refresh(force: true)
    XCTAssertEqual(monitor.textRGB565().count, 240 * 240 * 2)
}
```

Render the complete quote page to a 240×240 bitmap using AppKit, then encode every pixel as big-endian RGB565. Include title, wrapped quote, right-aligned author, language marker, and update time.

- [ ] **Step 7: Run tests and commit**

Run: `cd mac-app && swift test --filter QuoteMonitorTests`

Expected: PASS.

```bash
git add mac-app/Sources/AIClockBridge/QuoteMonitor.swift mac-app/Tests/AIClockBridgeTests/QuoteMonitorTests.swift
git commit -m "feat(mac): add bilingual quote monitor"
```

---

### Task 3: Publish Quotes and Auto Configuration Through the Bridge

**Files:**
- Modify: `mac-app/Sources/AIClockBridge/StatusReader.swift`
- Modify: `mac-app/Sources/AIClockBridge/main.swift`
- Modify: `mac-app/Sources/AIClockBridge/SerialLink.swift`
- Test: `mac-app/Tests/AIClockBridgeTests/AutoDisplaySettingsTests.swift`

**Interfaces:**
- Consumes: `AutoDisplaySettingsStore.jsonObject()` and `QuoteMonitor.jsonData()`
- Produces: `/quote`, `/quote/text.raw`, status key `auto_display`, and serial frame `#QUOTE `

- [ ] **Step 1: Write a failing status-payload composition test**

Extract a pure helper that merges the settings object into a status dictionary:

```swift
func testStatusPayloadContainsAutoDisplayConfiguration() {
    let payload = StatusPayloadComposer.addAutoDisplay(["version": "test"], settings: store)
    XCTAssertNotNil(payload["auto_display"] as? [String: Any])
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `cd mac-app && swift test --filter AutoDisplaySettingsTests/testStatusPayloadContainsAutoDisplayConfiguration`

Expected: FAIL because the composer/helper is absent.

- [ ] **Step 3: Wire settings into the status JSON**

Add a settings provider to `StatusService`, and merge `auto_display` immediately before `JSONSerialization`. Keep all existing status keys unchanged.

- [ ] **Step 4: Wire quote HTTP and serial routes**

In `main.swift`, instantiate and start `QuoteMonitor`, add `/quote` and `/quote/text.raw`, and include `/quote` in passive device discovery. Extend `SerialLink` to accept `QuoteMonitor`, send `#QUOTE ` every five seconds while linked, and leave the large raw bitmap HTTP-only.

- [ ] **Step 5: Verify endpoints with the focused test suite and build**

Run: `cd mac-app && swift test && swift build`

Expected: all tests PASS and build succeeds.

- [ ] **Step 6: Commit**

```bash
git add mac-app/Sources/AIClockBridge/StatusReader.swift mac-app/Sources/AIClockBridge/main.swift mac-app/Sources/AIClockBridge/SerialLink.swift mac-app/Tests/AIClockBridgeTests/AutoDisplaySettingsTests.swift
git commit -m "feat(mac): publish quote and auto display data"
```

---

### Task 4: Mac Settings Window, Menu Commands, and Mirror Page

**Files:**
- Create: `mac-app/Sources/AIClockBridge/AutoDisplaySettingsWindow.swift`
- Modify: `mac-app/Sources/AIClockBridge/MenuBarController.swift`
- Modify: `mac-app/Sources/AIClockBridge/MirrorPopover.swift`
- Modify: `mac-app/Sources/AIClockBridge/DeviceClient.swift`

**Interfaces:**
- Consumes: `AutoDisplaySettingsStore`, `QuoteMonitor`
- Produces: an AppKit settings window, `quote` fixed mode, “换一句”, and quote mirror rendering

- [ ] **Step 1: Implement the settings window with explicit field mapping**

Create one checkbox row for `claude`, `codex`, `approval`, and `music`. Create rows for `weather`, `quote`, `stock`, and `net` containing a checkbox, interval-in-minutes field, and duration-in-seconds field. On save, map every control back to `AutoDisplayConfiguration`, call `normalize()`, save through the store, and close only after persistence succeeds.

- [ ] **Step 2: Add menu integration**

Pass `settingsStore` and `quoteMonitor` into `MenuBarController`. Add:

```swift
menu.addItem(makeItem("自动显示设置…", #selector(openAutoDisplaySettings)))
menu.addItem(makeItem("换一句", #selector(nextQuote)))
```

Add `("名人名言", "quote")` to the fixed display submenu. `nextQuote` calls `await quoteMonitor.refresh(force: true)` and requests `quote` mode only when the current configured fixed mode is already `quote`.

- [ ] **Step 3: Add quote support to the client and device label**

Update `DeviceInfo` comments and parsing to recognize `quote`; display “名言” when `effective == "quote"`. Do not reject unknown future mode strings client-side.

- [ ] **Step 4: Add the mirror segment and page**

Extend the segment arrays in `MirrorPopover` with `quote`, add `quoteMode` and `quoteSnapshot`, and draw the same title/body/author/language structure as the RGB565 renderer. Keep the segment width usable by abbreviating the label to “言”.

- [ ] **Step 5: Build and manually inspect both windows**

Run: `cd mac-app && swift test && swift run`

Expected: settings reopen with saved values; Claude defaults off; quote appears in the menu and mirror; “换一句” updates content without freezing the menu.

- [ ] **Step 6: Commit**

```bash
git add mac-app/Sources/AIClockBridge/AutoDisplaySettingsWindow.swift mac-app/Sources/AIClockBridge/MenuBarController.swift mac-app/Sources/AIClockBridge/MirrorPopover.swift mac-app/Sources/AIClockBridge/DeviceClient.swift
git commit -m "feat(mac): add auto display controls and quote UI"
```

---

### Task 5: Generic Firmware Auto Scheduler

**Files:**
- Create: `firmware/include/auto_display_logic.h`
- Create: `firmware/test/test_auto_display/test_main.cpp`
- Modify: `firmware/include/weather_logic.h`
- Modify: `firmware/src/main.cpp`

**Interfaces:**
- Produces: `AutoDisplayConfig`, `ScheduledPageState`, `AutoSelectionInputs`, and `chooseAutoDisplay(...)`
- Consumes later: mode identifiers for weather, quote, stock, and net

- [ ] **Step 1: Write failing native scheduler tests**

```cpp
void testClaudeCanBeDisabled() {
  AutoSelectionInputs in{};
  in.claudeWorking = true;
  in.config.claudeEnabled = false;
  assert(chooseAutoDisplay(in) == AUTO_IDLE);
}

void testPriorityAndFairScheduledChoice() {
  AutoSelectionInputs in{};
  in.config.codexEnabled = true;
  in.codexWorking = true;
  in.musicPlaying = true;
  assert(chooseAutoDisplay(in) == AUTO_CODEX);
  in.codexWorking = false;
  assert(chooseAutoDisplay(in) == AUTO_MUSIC);
  in.musicPlaying = false;
  in.dueMask = AUTO_DUE_WEATHER | AUTO_DUE_QUOTE;
  in.lastShownWeather = 200;
  in.lastShownQuote = 100;
  assert(chooseAutoDisplay(in) == AUTO_QUOTE);
}
```

Also test approvals disabled, all items disabled, invalid range clamping, and scheduled validity masks.

- [ ] **Step 2: Run the native test and verify it fails**

Run: `cd firmware && clang++ -std=c++17 -Wall -Wextra -pedantic -Iinclude test/test_auto_display/test_main.cpp -o /tmp/auto_display_test`

Expected: compilation FAIL because `auto_display_logic.h` is absent.

- [ ] **Step 3: Implement pure scheduler types and selection**

Use explicit booleans for event items and an array of four scheduled settings indexed by weather, quote, stock, and net. Clamp seconds in a pure `normalizeAutoDisplayConfig`. `chooseAutoDisplay` first checks enabled approval, enabled working agents, enabled music, then selects the valid due page with the oldest `lastShown` timestamp.

- [ ] **Step 4: Replace weather-only window state in firmware**

Remove `weatherAutoDueMs` and `weatherAutoUntilMs`. Add a `ScheduledPageState` entry per scheduled page containing `dueMs`, `untilMs`, and `lastShownOrder`. Parse `auto_display` only when its `revision` differs, retaining defaults when the object or individual fields are absent.

When an event interrupts a scheduled page, clear its active window without advancing its due time. On return, select it again and grant the full configured duration.

- [ ] **Step 5: Run native scheduler and existing weather tests**

Run:

```bash
cd firmware
clang++ -std=c++17 -Wall -Wextra -pedantic -Iinclude test/test_auto_display/test_main.cpp -o /tmp/auto_display_test && /tmp/auto_display_test
clang++ -std=c++17 -Wall -Wextra -pedantic -Iinclude test/test_weather/test_main.cpp -o /tmp/weather_test && /tmp/weather_test
```

Expected: both PASS.

- [ ] **Step 6: Commit**

```bash
git add firmware/include/auto_display_logic.h firmware/include/weather_logic.h firmware/test/test_auto_display/test_main.cpp firmware/src/main.cpp
git commit -m "feat(firmware): add configurable automatic scheduler"
```

---

### Task 6: Firmware Quote Mode and Full Integration

**Files:**
- Modify: `firmware/src/main.cpp`
- Modify: `firmware/include/config.h`
- Test: `firmware/test/test_auto_display/test_main.cpp`

**Interfaces:**
- Consumes: bridge `/quote`, `/quote/text.raw`, `#QUOTE`, and generic scheduler
- Produces: `MODE_QUOTE`, quote JSON state, full-screen raw text draw, API/web mode support

- [ ] **Step 1: Add quote state and JSON parsing**

Add fields `valid`, `textRev`, `language`, `updatedAt`, and `stale`. Parse HTTP `/quote` and serial `#QUOTE` through one function. Only mark `valid` after non-empty text metadata is parsed; preserve the last valid state on a failed poll.

- [ ] **Step 2: Add fixed-size bitmap download and rendering**

Follow the weather raw-layer streaming implementation, but require exactly `240 * 240 * 2` bytes from `/quote/text.raw`. Draw into the full screen in chunks without holding the entire bitmap in RAM. Do not transition into quote mode until metadata is valid and the text revision can be fetched.

- [ ] **Step 3: Integrate quote mode everywhere modes are enumerated**

Add `MODE_QUOTE` to `DisplayMode`, `modeName`, `/api/display` parsing/error text, `/api/info`, bridge status parsing, loop transition clearing, polling, and the device web page selector. Bump firmware version from `0.4.12` to `0.4.13`.

- [ ] **Step 4: Exercise fixed and automatic quote paths**

Extend the native scheduler test so quote disabled never selects it, quote enabled selects when valid/due, and an invalid quote is skipped in favor of another due page.

- [ ] **Step 5: Build firmware and inspect resource limits**

Run: `cd firmware && .pio-venv/bin/pio run`

Expected: SUCCESS, RAM below 70%, Flash below 90%.

- [ ] **Step 6: Commit**

```bash
git add firmware/src/main.cpp firmware/include/config.h firmware/test/test_auto_display/test_main.cpp
git commit -m "feat(firmware): add quote display mode"
```

---

### Task 7: Documentation and End-to-End Verification

**Files:**
- Modify: `README.md`
- Modify: `README.en.md`
- Modify: `docs/DEVELOPMENT.md`

**Interfaces:**
- Documents: settings UI, quote sources, routes, serial frame, auto priority, update/flash steps

- [ ] **Step 1: Update user documentation**

Document「自动显示设置…」, event versus scheduled items, the default table, “名人名言” fixed mode, “换一句”, bilingual sources, caching, and the fact that disabling an item affects only automatic mode.

- [ ] **Step 2: Update developer documentation**

Add `/quote`, `/quote/text.raw`, `#QUOTE`, the `auto_display` schema, valid ranges, mode `quote`, compatibility behavior, and version `0.4.13`.

- [ ] **Step 3: Run all automated verification**

Run:

```bash
(cd mac-app && swift test && swift build)
(cd firmware && clang++ -std=c++17 -Wall -Wextra -pedantic -Iinclude test/test_weather/test_main.cpp -o /tmp/weather_test && /tmp/weather_test)
(cd firmware && clang++ -std=c++17 -Wall -Wextra -pedantic -Iinclude test/test_auto_display/test_main.cpp -o /tmp/auto_display_test && /tmp/auto_display_test)
(cd firmware && .pio-venv/bin/pio run)
git diff --check
```

Expected: all Swift tests PASS, both native binaries exit 0, PlatformIO reports SUCCESS within the resource limits, and `git diff --check` prints nothing.

- [ ] **Step 4: Perform available integration checks**

With no installed bridge occupying port 8765, run the new bridge and fetch `/status`, `/quote`, and `/quote/text.raw`; verify JSON fields and exactly 115,200 raw bytes. If hardware is attached, flash and exercise fixed quote mode, automatic selection, settings sync, interruption, and reconnect. Record hardware or port limitations explicitly when unavailable.

- [ ] **Step 5: Commit documentation**

```bash
git add README.md README.en.md docs/DEVELOPMENT.md
git commit -m "docs: document auto display and quotes"
```

- [ ] **Step 6: Final clean-tree review**

Run: `git status --short && git log --oneline -8`

Expected: no uncommitted files and a readable sequence of focused commits matching Tasks 1–7.
