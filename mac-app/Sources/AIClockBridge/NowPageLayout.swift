import AppKit
import Foundation

/// Input data for the composite "NOW" (此刻) page. All three sources already
/// exist in the bridge — the quote, weather and Codex monitors — so this page
/// adds no new network dependency: it only merges their latest snapshots into
/// one 240×240 card.
struct NowPageData {
    var quote: QuoteSnapshot?
    var weather: WeatherSnapshot?
    var codex: ProviderUsage
    var now: Date
}

/// Typography for the composite "NOW" page: the quote is the main block
/// (adaptive size, exactly like QuotePageLayout), with a compact weather strip
/// and the Codex weekly-quota bar + reset countdown pinned at the bottom.
/// Same conventions as QuotePageLayout — 240×240, top-left origin, one shared
/// geometry so the device bitmap and the menu-bar mirror render identically.
struct NowPageLayout {
    static let layoutRevision = 3
    static let pageSize = 240

    // Page geometry, top-left origin.
    private static let headerLogoRect = CGRect(x: 8, y: 8, width: 64, height: 16)
    private static let headerDateRect = CGRect(x: 144, y: 8, width: 88, height: 16)
    private static let bodyRect = CGRect(x: 14, y: 30, width: 212, height: 122)
    private static let authorRect = CGRect(x: 14, y: 156, width: 212, height: 16)
    private static let dividerRect = CGRect(x: 16, y: 172, width: 208, height: 1)
    private static let weather1Rect = CGRect(x: 16, y: 178, width: 208, height: 18)
    private static let weather2Rect = CGRect(x: 16, y: 197, width: 208, height: 14)
    private static let codexRowRect = CGRect(x: 16, y: 214, width: 208, height: 16)

    private enum Typography {
        static let headerSize: CGFloat = 10
        static let bodySizes: [String: ClosedRange<CGFloat>] = ["zh": 14...30, "en": 12...28]
        static let authorSizes: [CGFloat] = [12, 11, 10]
        static let characterLimits: [String: Int] = ["zh": 80, "en": 180]
        static let step: CGFloat = 0.5
        static let weatherSize: CGFloat = 12
        static let weatherSubSize: CGFloat = 9
        static let codexLabelSize: CGFloat = 9
        static let codexNumSize: CGFloat = 10
    }

    let headerLogo: QuoteTextRun
    let headerDate: QuoteTextRun
    let body: QuoteTextRun
    let author: QuoteTextRun
    let dividerRect: CGRect
    let weatherLine1: QuoteTextRun
    let weatherLine2: QuoteTextRun
    let codexLabel: QuoteTextRun
    let codexBarRect: CGRect
    let codexBarColor: NSColor
    let codexFillRatio: CGFloat
    let codexPct: QuoteTextRun
    let codexReset: QuoteTextRun
    /// False when the quote itself cannot fit even at the minimum size.
    /// Renderers still draw such a page (a cached quote should not blank the
    /// screen); NowPageMonitor keeps publishing as long as a quote exists.
    let fits: Bool

    var textRuns: [QuoteTextRun] {
        [headerLogo, headerDate, body, author, weatherLine1, weatherLine2,
         codexLabel, codexPct, codexReset]
    }

    // MARK: - make

    static func make(for data: NowPageData) -> NowPageLayout? {
        let text = data.quote?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let author = data.quote?.author.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let language = data.quote?.language == "en" ? "en" : "zh"
        guard !text.isEmpty,
              text.count <= (Typography.characterLimits[language] ?? 80) else { return nil }

        let body = bodyRun(text: text, language: language)
        let authorFit = authorRun(author: author)
        let pct = data.codex.weeklyPct
        let full = (pct ?? 0) >= 100
        let barColor: NSColor = pct.map {
            $0 >= 100 ? NSColor.systemRed
                : $0 >= 90 ? NSColor.systemYellow
                : NSColor.systemGreen
        } ?? NSColor.systemGray
        let resetColor: NSColor = full ? NSColor.systemRed : NSColor(white: 0.6, alpha: 1)
        let pctText = pct.map {
            let used = min(100, max(0, Int($0)))
            let remain = 100 - used
            return "\(remain)%"
        } ?? "暂无数据"
        let pctRect = CGRect(x: 132, y: 214, width: 92, height: 16)
        let pctColor = pct == nil ? NSColor(white: 0.6, alpha: 1) : NSColor.white
        let pctWeight: NSFont.Weight = pct == nil ? .regular : .semibold

        return NowPageLayout(
            headerLogo: headerRun("NOW", rect: headerLogoRect, color: NSColor.systemTeal),
            headerDate: infoRun(headerDateText(data.now), rect: headerDateRect,
                                size: Typography.headerSize, color: NSColor(white: 0.48, alpha: 1),
                                mono: true, right: true),
            body: body.run,
            author: authorFit.run,
            dividerRect: dividerRect,
            weatherLine1: infoRun(weatherLine1Text(data.weather), rect: weather1Rect,
                                  size: Typography.weatherSize, color: .white, weight: .medium),
            weatherLine2: infoRun(weatherLine2Text(data.weather), rect: weather2Rect,
                                  size: Typography.weatherSubSize, color: NSColor(white: 0.6, alpha: 1)),
            codexLabel: infoRun("CODEX", rect: CGRect(x: codexRowRect.minX, y: 215, width: 40, height: 14),
                                size: Typography.codexLabelSize, color: NSColor.systemTeal, weight: .semibold),
            codexBarRect: CGRect(x: 58, y: 219, width: 70, height: 4),
            codexBarColor: barColor,
            codexFillRatio: CGFloat(min(1, max(0, (pct ?? 0) / 100))),
            codexPct: infoRun(pctText, rect: pctRect,
                              size: Typography.codexNumSize, color: pctColor,
                              weight: pctWeight, mono: pct != nil),
            codexReset: infoRun(codexResetText(data.codex), rect: CGRect(x: 168, y: 215, width: 56, height: 14),
                                size: Typography.codexLabelSize, color: resetColor, mono: true, right: true),
            fits: body.fits && authorFit.fits
        )
    }

    // MARK: - runs

    private static func headerRun(_ text: String, rect: CGRect, color: NSColor) -> QuoteTextRun {
        infoRun(text, rect: rect, size: Typography.headerSize, color: color, weight: .semibold)
    }

    private static func infoRun(_ text: String, rect: CGRect, size: CGFloat, color: NSColor,
                                weight: NSFont.Weight = .regular, mono: Bool = false,
                                right: Bool = false) -> QuoteTextRun {
        let style = NSMutableParagraphStyle()
        style.alignment = right ? .right : .left
        style.lineBreakMode = .byTruncatingTail
        let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                        : NSFont.systemFont(ofSize: size, weight: weight)
        return QuoteTextRun(text: text, rect: rect, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ])
    }

    private static func authorRun(author: String) -> (run: QuoteTextRun, fits: Bool) {
        let text = "— \(author)"
        for size in Typography.authorSizes {
            let attributes = authorAttributes(size: size)
            let bounds = (text as NSString).boundingRect(
                with: NSSize(width: .greatestFiniteMagnitude, height: authorRect.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            )
            if ceil(bounds.width) <= authorRect.width, ceil(bounds.height) <= authorRect.height {
                return (QuoteTextRun(text: text, rect: authorRect, attributes: attributes), true)
            }
        }
        let size = Typography.authorSizes.last!
        return (QuoteTextRun(text: text, rect: authorRect, attributes: authorAttributes(size: size)), false)
    }

    private static func bodyRun(text: String, language: String) -> (run: QuoteTextRun, fits: Bool) {
        let range = Typography.bodySizes[language] ?? Typography.bodySizes["zh"]!
        let chinese = language == "zh"
        let display = bodyDisplayText(text, chinese: chinese)
        var size = range.upperBound
        var fitted: (size: CGFloat, height: CGFloat)?

        while size >= range.lowerBound - 0.001 {
            if let height = measuredHeight(display, size: size, chinese: chinese), height <= bodyRect.height {
                let attributes = bodyAttributes(size: size, chinese: chinese, centered: false)
                let expectedLines = display.reduce(into: 1) { count, character in
                    if character == "\n" { count += 1 }
                }
                let respectsClauseBreak = !display.contains("\n") ||
                    lineCount(display, attributes: attributes, width: bodyRect.width) == expectedLines
                if respectsClauseBreak &&
                    (!chinese || hasReadableLines(display, attributes: attributes, width: bodyRect.width)) {
                    fitted = (size, height)
                    break
                }
            }
            size -= Typography.step
        }

        let resolved = fitted ?? (range.lowerBound,
                                  measuredHeight(display, size: range.lowerBound, chinese: chinese) ?? bodyRect.height)
        let leftAttributes = bodyAttributes(size: resolved.size, chinese: chinese, centered: false)
        // One or two lines read well centred; longer quotes stay left-aligned.
        let centered = lineCount(display, attributes: leftAttributes, width: bodyRect.width) <= 2
        let attributes = bodyAttributes(size: resolved.size, chinese: chinese, centered: centered)
        let rect = CGRect(x: bodyRect.minX,
                          y: bodyRect.minY + (bodyRect.height - resolved.height) / 2,
                          width: bodyRect.width,
                          height: resolved.height)
        return (QuoteTextRun(text: display, rect: rect, attributes: attributes), fitted != nil)
    }

    private static func bodyDisplayText(_ text: String, chinese: Bool) -> String {
        guard chinese else { return "“\(text)”" }
        let preferredBreaks = CharacterSet(charactersIn: "，；！？")
        var candidates: [(index: String.Index, balance: Int)] = []
        for index in text.indices where String(text[index]).rangeOfCharacter(from: preferredBreaks) != nil {
            let next = text.index(after: index)
            let leading = text.distance(from: text.startIndex, to: next)
            let trailing = text.distance(from: next, to: text.endIndex)
            if leading >= 4 && trailing >= 4 {
                candidates.append((next, abs(leading - trailing)))
            }
        }
        guard let split = candidates.min(by: { $0.balance < $1.balance })?.index else {
            return "“\(text)”"
        }
        let preferred = "“\(text[..<split])\n\(text[split...])”"
        let minimumSize = Typography.bodySizes["zh"]!.lowerBound
        let attributes = bodyAttributes(size: minimumSize, chinese: true, centered: false)
        return lineCount(preferred, attributes: attributes, width: bodyRect.width) == 2
            ? preferred
            : "“\(text)”"
    }

    // MARK: - measurement

    private static func measuredHeight(_ text: String, size: CGFloat, chinese: Bool) -> CGFloat? {
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: bodyRect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: bodyAttributes(size: size, chinese: chinese, centered: false)
        )
        guard ceil(bounds.width) <= bodyRect.width else { return nil }
        return ceil(bounds.height)
    }

    private static func lineCount(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) -> Int {
        lineRanges(text, attributes: attributes, width: width).count
    }

    private static func hasReadableLines(_ text: String, attributes: [NSAttributedString.Key: Any],
                                         width: CGFloat) -> Bool {
        let punctuation = CharacterSet(charactersIn: "，。！？、；：“”‘’（）【】《》「」『』,.!?;:")
        let ignored = punctuation.union(.whitespacesAndNewlines)
        let source = text as NSString
        return lineRanges(text, attributes: attributes, width: width).allSatisfy { range in
            !source.substring(with: NSRange(location: range.location, length: range.length))
                .trimmingCharacters(in: ignored).isEmpty
        }
    }

    private static func lineRanges(_ text: String, attributes: [NSAttributedString.Key: Any],
                                   width: CGFloat) -> [CFRange] {
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        return (CTFrameGetLines(frame) as NSArray).map { CTLineGetStringRange($0 as! CTLine) }
    }

    // MARK: - attributes

    private static func bodyAttributes(size: CGFloat, chinese: Bool, centered: Bool) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        // Chinese has no word boundaries → break per character; English per word.
        style.lineBreakMode = chinese ? .byCharWrapping : .byWordWrapping
        style.alignment = centered ? .center : .left
        style.lineSpacing = round(size * 0.12)
        return [
            .font: NSFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: style,
        ]
    }

    private static func authorAttributes(size: CGFloat) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byClipping
        style.alignment = .right
        return [
            .font: NSFont.systemFont(ofSize: size, weight: .regular),
            .foregroundColor: NSColor(white: 0.75, alpha: 1),
            .paragraphStyle: style,
        ]
    }

    // MARK: - display strings (shared by the monitor, mirror and tests)

    static func weatherLine1Text(_ weather: WeatherSnapshot?) -> String {
        guard let weather else { return "天气暂无数据" }
        let temp = weather.temperature.map { "\(Int($0.rounded()))°C" } ?? "--"
        return "\(weatherIcon(weather.weatherCode)) \(weather.city) · \(temp) · \(WeatherMonitor.conditionText(for: weather.weatherCode))"
    }

    static func weatherLine2Text(_ weather: WeatherSnapshot?) -> String {
        guard let weather else { return "" }
        var parts: [String] = []
        if let high = weather.high { parts.append("高\(Int(high.rounded()))°") }
        if let low = weather.low { parts.append("低\(Int(low.rounded()))°") }
        if let humidity = weather.humidity { parts.append("湿度\(humidity)%") }
        if let aqi = weather.aqi { parts.append(WeatherMonitor.aqiGrade(aqi)) }
        return parts.joined(separator: " · ")
    }

    static func codexResetText(_ usage: ProviderUsage) -> String {
        guard let minutes = usage.weeklyResetMin, minutes >= 0 else { return "" }
        if minutes < 60 { return "\(minutes)分" }
        let hours = minutes / 60
        if hours < 24 {
            let m = minutes % 60
            return m == 0 ? "\(hours)时" : "\(hours)时\(m)分"
        }
        let days = hours / 24
        let rest = hours % 24
        return rest == 0 ? "\(days)天" : "\(days)天\(rest)时"
    }

    static func headerDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM.dd · HH:mm"
        return formatter.string(from: date)
    }

    static func weatherIcon(_ code: Int) -> String {
        switch WeatherMonitor.icon(for: code) {
        case .clear: return "☀"
        case .partlyCloudy: return "⛅"
        case .cloudy: return "☁"
        case .overcast: return "☁"
        case .fog: return "🌫"
        case .rain: return "🌧"
        case .showers: return "🌦"
        case .snow: return "❄"
        case .thunderstorm: return "⛈"
        case .unknown: return "?"
        }
    }

    /// Content revision sent to the firmware: any visible change (quote text
    /// rev, weather rev, Codex pct / reset minutes) bumps it, so the device
    /// refetches the composite bitmap only when something actually changed.
    static func rev(for data: NowPageData) -> Int {
        var r = 0
        r = r &* 31 &+ layoutRevision
        if let quote = data.quote { r = r &* 31 &+ quote.textRev }
        if let weather = data.weather { r = r &* 31 &+ weather.textRev }
        let pct = Int((data.codex.weeklyPct ?? -1).rounded())
        r = r &* 31 &+ pct
        r = r &* 31 &+ (data.codex.weeklyResetMin ?? -1)
        return r
    }

    // MARK: - bitmap render (device wire format)

    static func renderRGB565(_ data: NowPageData) -> Data {
        let size = pageSize
        guard let layout = make(for: data),
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return Data(count: size * size * 2)
        }
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for run in layout.textRuns {
            (run.text as NSString).draw(in: run.deviceRect(pageHeight: CGFloat(size)),
                                        withAttributes: run.attributes)
        }
        NSGraphicsContext.restoreGraphicsState()

        // Divider + Codex quota bar (non-flipped context → convert top-left rects).
        context.setFillColor(NSColor(white: 0.25, alpha: 1).cgColor)
        context.fill(deviceRect(layout.dividerRect))
        context.setFillColor(NSColor(white: 0.2, alpha: 1).cgColor)
        context.fill(deviceRect(layout.codexBarRect))
        let fillWidth = layout.codexBarRect.width * layout.codexFillRatio
        if fillWidth > 0 {
            context.setFillColor(layout.codexBarColor.cgColor)
            context.fill(deviceRect(CGRect(x: layout.codexBarRect.minX, y: layout.codexBarRect.minY,
                                           width: fillWidth, height: layout.codexBarRect.height)))
        }
        return RGB565.encode(from: context, width: size, height: size)
    }

    private static func deviceRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: CGFloat(pageSize) - rect.maxY, width: rect.width, height: rect.height)
    }
}
