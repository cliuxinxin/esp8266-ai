import AppKit
import Foundation

/// One piece of text on the 240×240 quote page.
///
/// `rect` is stored in the top-left origin space `MirrorPopover` draws in.
/// `deviceRect()` mirrors it for the non-flipped `CGContext` that produces the
/// RGB565 bitmap sent to the ESP8266, so both renderers share one geometry.
struct QuoteTextRun {
    let text: String
    let rect: CGRect
    let attributes: [NSAttributedString.Key: Any]

    func deviceRect(pageHeight: CGFloat = CGFloat(QuotePageLayout.pageSize)) -> CGRect {
        CGRect(x: rect.minX, y: pageHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// Typography for the quote page.
///
/// Body and author sizes are chosen per quote instead of being fixed: a five
/// character Chinese quote fills the screen, while a four line English one
/// shrinks until it fits. Both renderers read the same numbers, so the menu bar
/// mirror always matches the device.
struct QuotePageLayout {
    static let pageSize = 240

    let title: QuoteTextRun
    let body: QuoteTextRun
    let author: QuoteTextRun
    let footer: QuoteTextRun

    /// False when even the smallest allowed size overflows its box. Renderers
    /// still draw such a page (a stale cached quote should not go blank);
    /// `QuoteMonitor` refuses to publish one.
    let fits: Bool

    var runs: [QuoteTextRun] { [title, body, author, footer] }

    // Page geometry, top-left origin: title / body / author / footer stacked
    // with a 10px top margin and a 12px bottom margin.
    private static let titleRect = CGRect(x: 8, y: 10, width: 224, height: 18)
    private static let bodyRect = CGRect(x: 16, y: 36, width: 208, height: 150)
    private static let authorRect = CGRect(x: 16, y: 190, width: 208, height: 18)
    private static let footerRect = CGRect(x: 16, y: 212, width: 208, height: 16)

    private enum Typography {
        static let titleSize: CGFloat = 11
        static let footerSize: CGFloat = 9
        static let bodySizes: [String: ClosedRange<CGFloat>] = ["zh": 15...30, "en": 13...26]
        static let authorSizes: [CGFloat] = [13, 12, 11, 10]
        static let characterLimits: [String: Int] = ["zh": 80, "en": 180]
        static let step: CGFloat = 0.5
    }

    static func make(for quote: QuoteSnapshot) -> QuotePageLayout? {
        let text = quote.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = quote.author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !author.isEmpty,
              text.count <= (Typography.characterLimits[quote.language] ?? 80) else {
            return nil
        }
        let body = bodyRun(text: text, language: quote.language)
        let authorRun = self.authorRun(author: author)
        return QuotePageLayout(
            title: titleRun(),
            body: body.run,
            author: authorRun.run,
            footer: footerRun(for: quote),
            fits: body.fits && authorRun.fits
        )
    }

    // MARK: - Runs

    private static func titleRun() -> QuoteTextRun {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return QuoteTextRun(text: "DAILY QUOTE", rect: titleRect, attributes: [
            .font: NSFont.systemFont(ofSize: Typography.titleSize, weight: .semibold),
            .foregroundColor: NSColor.systemTeal,
            .paragraphStyle: style,
        ])
    }

    private static func footerRun(for quote: QuoteSnapshot) -> QuoteTextRun {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let text = "\(quote.language.uppercased())  ·  \(formatter.string(from: quote.updatedAt))"
        return QuoteTextRun(text: text, rect: footerRect, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: Typography.footerSize, weight: .regular),
            .foregroundColor: NSColor(white: 0.48, alpha: 1),
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
        let display = "“\(text)”"
        var size = range.upperBound
        var fitted: (size: CGFloat, height: CGFloat)?

        while size >= range.lowerBound - 0.001 {
            if let height = measuredHeight(display, size: size, chinese: chinese), height <= bodyRect.height {
                fitted = (size, height)
                break
            }
            size -= Typography.step
        }

        let resolved = fitted ?? (range.lowerBound,
                                  measuredHeight(display, size: range.lowerBound, chinese: chinese) ?? bodyRect.height)
        let leftAttributes = bodyAttributes(size: resolved.size, chinese: chinese, centered: false)
        // Short quotes (one or two lines) read well centred; longer ones stay
        // left-aligned for easier reading.
        let centered = lineCount(display, attributes: leftAttributes, width: bodyRect.width) <= 2
        let attributes = bodyAttributes(size: resolved.size, chinese: chinese, centered: centered)
        // Vertically centre the block so short quotes sit in the middle of the
        // screen instead of hugging the title.
        let rect = CGRect(x: bodyRect.minX,
                          y: bodyRect.minY + (bodyRect.height - resolved.height) / 2,
                          width: bodyRect.width,
                          height: resolved.height)
        return (QuoteTextRun(text: display, rect: rect, attributes: attributes), fitted != nil)
    }

    // MARK: - Measurement

    private static func measuredHeight(_ text: String, size: CGFloat, chinese: Bool) -> CGFloat? {
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: bodyRect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: bodyAttributes(size: size, chinese: chinese, centered: false)
        )
        // An unbreakable run wider than the box never recovers by shrinking
        // gracefully, so treat it as "does not fit" and keep stepping down.
        guard ceil(bounds.width) <= bodyRect.width else { return nil }
        return ceil(bounds.height)
    }

    private static func lineCount(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) -> Int {
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        return CFArrayGetCount(CTFrameGetLines(frame))
    }

    // MARK: - Attributes

    private static func bodyAttributes(size: CGFloat, chinese: Bool, centered: Bool) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        // Chinese has no word boundaries, so break per character; English breaks
        // per word and keeps hyphenation out of the small screen.
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
}
