import XCTest
@testable import AIClockBridge

final class NowPageLayoutTests: XCTestCase {
    private func renderedLines(_ run: QuoteTextRun) -> [String] {
        let attributed = NSAttributedString(string: run.text, attributes: run.attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: run.rect.width,
                                       height: .greatestFiniteMagnitude), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        let text = run.text as NSString
        return (CTFrameGetLines(frame) as NSArray).compactMap { value in
            let range = CTLineGetStringRange(value as! CTLine)
            guard range.location != kCFNotFound else { return nil }
            return text.substring(with: NSRange(location: range.location, length: range.length))
                .trimmingCharacters(in: .newlines)
        }
    }

    private func quote(text: String, author: String, language: String,
                       revision: Int = 1) -> QuoteSnapshot {
        QuoteSnapshot(text: text, author: author, language: language,
                      updatedAt: Date(timeIntervalSince1970: 1_000), textRev: revision)
    }

    private func weather(temperature: Double? = 22, high: Double? = 26, low: Double? = 18,
                         humidity: Int? = 62, aqi: Int? = 30, code: Int = 0,
                         city: String = "成都") -> WeatherSnapshot {
        WeatherSnapshot(city: city, updatedAt: Date(timeIntervalSince1970: 2_000),
                        weatherCode: code, temperature: temperature,
                        apparentTemperature: temperature, high: high, low: low,
                        humidity: humidity, precipitationProbability: nil,
                        windSpeed: nil, windDirectionDegrees: nil, windDirection: "北",
                        aqi: aqi, forecast: [], textRev: 1)
    }

    private func codex(weeklyPct: Double? = 42, weeklyResetMin: Int? = 342,
                       primaryPct: Double? = nil, primaryResetMin: Int? = nil) -> ProviderUsage {
        ProviderUsage(primaryPct: primaryPct, primaryResetMin: primaryResetMin,
                      weeklyPct: weeklyPct, weeklyResetMin: weeklyResetMin,
                      error: nil, fetchedAt: Date())
    }

    private func data(quote: QuoteSnapshot? = nil, weather: WeatherSnapshot? = nil,
                      codex: ProviderUsage? = nil, now: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> NowPageData {
        NowPageData(quote: quote, weather: weather, codex: codex ?? self.codex(), now: now)
    }

    // MARK: - weather strings

    func testWeatherLine1FormatsCityTempAndCondition() {
        XCTAssertEqual(NowPageLayout.weatherLine1Text(weather()),
                       "☀ 成都 · 22°C · 晴")
        XCTAssertEqual(NowPageLayout.weatherLine1Text(weather(code: 3)),
                       "☁ 成都 · 22°C · 阴")
        XCTAssertEqual(NowPageLayout.weatherLine1Text(weather(temperature: nil)),
                       "☀ 成都 · -- · 晴")
        XCTAssertEqual(NowPageLayout.weatherLine1Text(nil), "天气暂无数据")
    }

    func testWeatherLine2ListsHighLowHumidityAndAqi() {
        XCTAssertEqual(NowPageLayout.weatherLine2Text(weather()),
                       "高26° · 低18° · 湿度62% · 优")
        XCTAssertEqual(NowPageLayout.weatherLine2Text(weather(humidity: nil, aqi: nil)),
                       "高26° · 低18°")
        XCTAssertEqual(NowPageLayout.weatherLine2Text(nil), "")
    }

    // MARK: - Codex reset formatting

    func testCodexResetTextUsesMinutesHoursAndDays() {
        XCTAssertEqual(NowPageLayout.codexResetText(codex(weeklyResetMin: 43)), "43分")
        XCTAssertEqual(NowPageLayout.codexResetText(codex(weeklyResetMin: 342)), "5时42分")
        XCTAssertEqual(NowPageLayout.codexResetText(codex(weeklyResetMin: 300)), "5时")
        XCTAssertEqual(NowPageLayout.codexResetText(codex(weeklyResetMin: 74 * 60 + 30)), "3天2时")
        XCTAssertEqual(NowPageLayout.codexResetText(codex(weeklyResetMin: 48 * 60)), "2天")
        XCTAssertEqual(NowPageLayout.codexResetText(codex(weeklyResetMin: nil)), "")
    }

    func testMissingCodexUsageUsesOneClearEmptyState() {
        let base = quote(text: "生活不止眼前的苟且", author: "高晓松", language: "zh")
        let missing = ProviderUsage(primaryPct: nil, primaryResetMin: nil,
                                    weeklyPct: nil, weeklyResetMin: nil,
                                    error: nil, fetchedAt: nil)
        let layout = NowPageLayout.make(for: data(quote: base, codex: missing))

        XCTAssertEqual(layout?.codexPct.text, "暂无数据")
        XCTAssertEqual(layout?.codexReset.text, "")
    }

    func testCodexPctPrefersWeeklyWindow() {
        let base = quote(text: "生活不止眼前的苟且", author: "高晓松", language: "zh")
        let both = codex(weeklyPct: 42, primaryPct: 10)
        let pct = NowPageLayout.make(for: data(quote: base, codex: both))?.codexPct.text ?? ""
        XCTAssertEqual(pct, "余58%")
        let weeklyOnly = codex(weeklyPct: 88)
        XCTAssertEqual(NowPageLayout.make(for: data(quote: base, codex: weeklyOnly))?.codexPct.text, "余12%")
    }

    // MARK: - header

    func testHeaderDateIsCompact() {
        let d = Date(timeIntervalSince1970: 1_724_500_000)
        let text = NowPageLayout.headerDateText(d)
        XCTAssertTrue(text.range(of: #"^\d{2}\.\d{2} · \d{2}:\d{2}$"#, options: .regularExpression) != nil,
                      "unexpected header date format: \(text)")
    }

    func testHeaderDateFitsWithoutTruncation() throws {
        let layout = try XCTUnwrap(NowPageLayout.make(for: data(quote: quote(
            text: "山高水长", author: "古语", language: "zh"))))
        let run = layout.headerDate
        let bounds = (run.text as NSString).boundingRect(
            with: NSSize(width: .greatestFiniteMagnitude, height: run.rect.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: run.attributes
        )

        XCTAssertLessThanOrEqual(ceil(bounds.width), run.rect.width)
    }

    // MARK: - layout geometry

    func testShortQuoteLayoutFitsAndStaysInsideBounds() {
        let layout = NowPageLayout.make(for: data(quote: quote(text: "知者不惑，仁者不忧。", author: "孔子", language: "zh")))
        XCTAssertNotNil(layout)
        XCTAssertTrue(layout!.fits)
        XCTAssertEqual(layout!.textRuns.count, 9) // logo, date, body, author, weather×2, codex×3
        for run in layout!.textRuns {
            XCTAssertGreaterThanOrEqual(run.rect.minX, 0)
            XCTAssertLessThanOrEqual(run.rect.maxY, 240)
        }
        XCTAssertEqual(layout!.codexBarRect.width, 70)
        XCTAssertEqual(layout!.dividerRect.width, 208)
    }

    func testLongQuoteShrinksInsideBodyBounds() {
        // 60 CJK chars is within the display limit; adaptive sizing must keep
        // the whole block inside the 208x120 body box (multi-line, shrunk).
        let layout = NowPageLayout.make(for: data(quote: quote(
            text: String(repeating: "长", count: 60), author: "作者", language: "zh")))
        XCTAssertNotNil(layout)
        XCTAssertGreaterThanOrEqual(layout!.body.rect.height, 1)
        XCTAssertLessThanOrEqual(layout!.body.rect.height, 120)
        XCTAssertLessThanOrEqual(layout!.body.rect.maxY, 240)
    }

    func testChineseQuoteNeverLeavesPunctuationOnlyLine() throws {
        let layout = try XCTUnwrap(NowPageLayout.make(for: data(quote: quote(
            text: "漫天风雪我陪你颤抖，我们别回头。", author: "林俊杰", language: "zh"))))
        let punctuation = CharacterSet(charactersIn: "，。！？、；：“”‘’（）【】《》「」『』,.!?;:")
        let lines = renderedLines(layout.body)

        XCTAssertFalse(lines.isEmpty)
        XCTAssertTrue(lines.allSatisfy {
            !$0.trimmingCharacters(in: punctuation.union(.whitespacesAndNewlines)).isEmpty
        }, "punctuation-only line in \(lines)")
    }

    func testChineseQuotePrefersClauseBoundaryOverSplittingAWord() throws {
        let layout = try XCTUnwrap(NowPageLayout.make(for: data(quote: quote(
            text: "漫天风雪我陪你颤抖，我们别回头。", author: "林俊杰", language: "zh"))))

        XCTAssertEqual(renderedLines(layout.body), ["“漫天风雪我陪你颤抖，", "我们别回头。”"])
    }

    func testLongChineseQuoteDoesNotForceAnImpossibleTwoLineClauseBreak() throws {
        let text = String(repeating: "长", count: 30) + "，" + String(repeating: "远", count: 29)
        let layout = try XCTUnwrap(NowPageLayout.make(for: data(quote: quote(
            text: text, author: "作者", language: "zh"))))

        XCTAssertTrue(layout.fits)
        XCTAssertGreaterThan(renderedLines(layout.body).count, 2)
    }

    func testOverLimitQuoteReturnsNil() {
        // Beyond the per-language display limit (80 zh), the page is refused
        // so a too-long sentence never gets published to the device.
        XCTAssertNil(NowPageLayout.make(for: data(quote: quote(
            text: String(repeating: "长", count: 81), author: "作者", language: "zh"))))
    }

    func testNoQuoteReturnsNil() {
        XCTAssertNil(NowPageLayout.make(for: data(quote: nil)))
    }

    // MARK: - bitmap

    func testRenderedBitmapHasExpectedByteCountAndContent() {
        let bitmap = NowPageLayout.renderRGB565(data(
            quote: quote(text: "Stay hungry, stay foolish.", author: "Steve Jobs", language: "en"),
            weather: weather()
        ))
        XCTAssertEqual(bitmap.count, 240 * 240 * 2)
        let bytes = [UInt8](bitmap)
        let nonzero = bytes.filter { $0 != 0 }.count
        XCTAssertGreaterThan(nonzero, 1000) // text + bar rows produce visible pixels
    }

    // MARK: - revision

    func testRevChangesOnlyWhenVisibleInputChanges() {
        let a = data(quote: quote(text: "山高水长", author: "古语", language: "zh", revision: 3),
                     weather: weather(), codex: codex(weeklyPct: 42, weeklyResetMin: 342))
        let same = data(quote: quote(text: "山高水长", author: "古语", language: "zh", revision: 3),
                        weather: weather(), codex: codex(weeklyPct: 42, weeklyResetMin: 342),
                        now: Date(timeIntervalSince1970: 999_999_999)) // time is NOT part of rev
        XCTAssertEqual(NowPageLayout.rev(for: a), NowPageLayout.rev(for: same))
        XCTAssertNotEqual(NowPageLayout.rev(for: a),
                          NowPageLayout.rev(for: data(quote: quote(text: "山高水长", author: "古语", language: "zh", revision: 4))))
        XCTAssertNotEqual(NowPageLayout.rev(for: a),
                          NowPageLayout.rev(for: data(codex: codex(weeklyPct: 88, weeklyResetMin: 342))))
    }

    func testNowMetadataPublishesLayoutRevisionForDeviceCacheInvalidation() throws {
        let json = NowPageMonitor.metadataJSON(revision: 37, available: true)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])

        XCTAssertEqual(object["rev"] as? Int, 37)
        XCTAssertEqual(object["layout_rev"] as? Int, 2)
        XCTAssertEqual(object["available"] as? Bool, true)
    }
}
