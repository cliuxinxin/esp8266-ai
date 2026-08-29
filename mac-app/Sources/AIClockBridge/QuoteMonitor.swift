import AppKit
import Foundation

protocol QuoteHTTPClient {
    func data(from url: URL) async throws -> Data
}

struct URLSessionQuoteClient: QuoteHTTPClient {
    func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

struct QuoteSnapshot: Codable, Equatable {
    let text: String
    let author: String
    let language: String
    let updatedAt: Date
    let textRev: Int

    enum CodingKeys: String, CodingKey {
        case text, author, language
        case updatedAt = "updated_at"
        case textRev = "text_rev"
    }

    func jsonData(now: Date = Date(), staleAfter: TimeInterval = 30 * 60) -> Data {
        let object: [String: Any] = [
            "text": text,
            "author": author,
            "language": language,
            "updated_at": Int(updatedAt.timeIntervalSince1970),
            "text_rev": textRev,
            "stale": now.timeIntervalSince(updatedAt) > staleAfter,
        ]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    }
}

final class QuoteMonitor {
    private static let hitokotoURL = URL(string: "https://v1.hitokoto.cn/?encode=json&c=d&c=k")!
    private static let zenQuotesURL = URL(string: "https://zenquotes.io/api/random")!
    private static let maxRecentTexts = 20
    private static let maxContentAttempts = 3
    private static let cacheVersion = 1
    private static let bodyRect = NSRect(x: 16, y: 58, width: 208, height: 145)
    private static let authorRect = NSRect(x: 16, y: 37, width: 208, height: 18)

    private let client: QuoteHTTPClient
    private let cacheURL: URL
    private let nowProvider: () -> Date
    private let staleAfter: TimeInterval
    private let errorReporter: (Error) -> Void
    private let lock = NSLock()
    private var storedSnapshot: QuoteSnapshot?
    private var storedText = Data()
    private var latestChinese: QuoteSnapshot?
    private var latestEnglish: QuoteSnapshot?
    private var recentTexts: [String] = []
    private var refreshInFlight = false
    private var refreshPending = false
    private var timer: Timer?

    init(client: QuoteHTTPClient = URLSessionQuoteClient(), cacheURL: URL? = nil,
         now: @escaping () -> Date = Date.init, staleAfter: TimeInterval = 30 * 60,
         errorReporter: @escaping (Error) -> Void = {
             FileHandle.standardError.write(Data("[quote] refresh failed: \($0)\n".utf8))
         }) {
        self.client = client
        self.cacheURL = cacheURL ?? Self.defaultCacheURL()
        self.nowProvider = now
        self.staleAfter = staleAfter
        self.errorReporter = errorReporter
        let loadedCache = Self.loadCache(from: self.cacheURL)
        latestChinese = loadedCache.envelope.latestChinese
        latestEnglish = loadedCache.envelope.latestEnglish
        recentTexts = loadedCache.envelope.recentTexts
        if let cached = loadedCache.envelope.currentSnapshot {
            storedSnapshot = cached
            storedText = Self.renderQuotePage(cached)
        }
        if loadedCache.migratedLegacySnapshot {
            Self.persist(loadedCache.envelope, to: self.cacheURL)
        }
    }

    var snapshot: QuoteSnapshot? { withStateLock { storedSnapshot } }

    func jsonData() -> Data {
        withStateLock {
            storedSnapshot?.jsonData(now: nowProvider(), staleAfter: staleAfter)
                ?? Data("{\"available\":false}".utf8)
        }
    }

    func textRGB565() -> Data { withStateLock { storedText } }

    func start() {
        Task { await refresh(force: false) }
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { await self?.refresh(force: false) }
        }
    }

    func refresh(force: Bool = false) async {
        guard beginRefresh(force: force) else { return }
        defer {
            if finishRefresh() {
                Task { await self.refresh(force: true) }
            }
        }

        let preferredLanguage = withStateLock { storedSnapshot?.language == "zh" ? "en" : "zh" }
        let fallbackLanguage = preferredLanguage == "zh" ? "en" : "zh"
        var lastError: Error?
        for attempt in 0..<Self.maxContentAttempts {
            do {
                let language = attempt.isMultiple(of: 2) ? preferredLanguage : fallbackLanguage
                let quote = try await fetch(language: language)
                guard Self.isDisplayable(quote) else {
                    lastError = QuoteMonitorError.notDisplayable
                    continue
                }
                guard !withStateLock({ recentTexts.contains(quote.text) }) else {
                    lastError = QuoteMonitorError.duplicate
                    continue
                }
                publish(quote)
                return
            } catch {
                lastError = error
            }
        }
        if let lastError { errorReporter(lastError) }
    }

    static func isDisplayable(_ quote: QuoteSnapshot) -> Bool {
        let count = quote.text.count
        guard !quote.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !quote.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              count <= (quote.language == "zh" ? 80 : 180) else {
            return false
        }

        let bodyBounds = ("“\(quote.text)”" as NSString).boundingRect(
            with: NSSize(width: bodyRect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: bodyTextAttributes(for: quote.language)
        )
        let authorBounds = ("— \(quote.author)" as NSString).boundingRect(
            with: NSSize(width: .greatestFiniteMagnitude, height: authorRect.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: authorTextAttributes()
        )
        return ceil(bodyBounds.width) <= bodyRect.width
            && ceil(bodyBounds.height) <= bodyRect.height
            && ceil(authorBounds.width) <= authorRect.width
            && ceil(authorBounds.height) <= authorRect.height
    }

    static func parseHitokoto(_ data: Data) throws -> QuoteSnapshot {
        let response = try JSONDecoder().decode(HitokotoResponse.self, from: data)
        let author = normalized(response.fromWho) ?? normalized(response.source) ?? "佚名"
        return QuoteSnapshot(text: normalizedText(response.text), author: author, language: "zh",
                             updatedAt: Date(), textRev: 0)
    }

    static func parseZenQuotes(_ data: Data) throws -> QuoteSnapshot {
        guard let response = try JSONDecoder().decode([ZenQuoteResponse].self, from: data).first else {
            throw QuoteMonitorError.emptyResponse
        }
        return QuoteSnapshot(text: normalizedText(response.text), author: normalized(response.author) ?? "Anonymous",
                             language: "en", updatedAt: Date(), textRev: 0)
    }

    private func fetch(language: String) async throws -> QuoteSnapshot {
        let data = try await client.data(from: language == "zh" ? Self.hitokotoURL : Self.zenQuotesURL)
        let parsed = try (language == "zh" ? Self.parseHitokoto(data) : Self.parseZenQuotes(data))
        let oldRevision = withStateLock { storedSnapshot?.textRev ?? 0 }
        return QuoteSnapshot(text: parsed.text, author: parsed.author, language: parsed.language,
                             updatedAt: nowProvider(), textRev: oldRevision + 1)
    }

    private func publish(_ quote: QuoteSnapshot) {
        let rendered = Self.renderQuotePage(quote)
        let envelope = withStateLock {
            storedSnapshot = quote
            storedText = rendered
            if quote.language == "zh" {
                latestChinese = quote
            } else {
                latestEnglish = quote
            }
            appendRecent(quote.text)
            return cacheEnvelope()
        }
        Self.persist(envelope, to: cacheURL)
    }

    private func beginRefresh(force: Bool) -> Bool {
        withStateLock {
            guard !refreshInFlight else {
                if force { refreshPending = true }
                return false
            }
            refreshInFlight = true
            return true
        }
    }

    private func finishRefresh() -> Bool {
        withStateLock {
            refreshInFlight = false
            let pending = refreshPending
            refreshPending = false
            return pending
        }
    }

    private func appendRecent(_ text: String) {
        recentTexts.removeAll { $0 == text }
        recentTexts.append(text)
        if recentTexts.count > Self.maxRecentTexts {
            recentTexts.removeFirst(recentTexts.count - Self.maxRecentTexts)
        }
    }

    private func cacheEnvelope() -> QuoteCacheEnvelope {
        QuoteCacheEnvelope(version: Self.cacheVersion, latestChinese: latestChinese,
                           latestEnglish: latestEnglish, recentTexts: recentTexts)
    }

    private static func loadCache(from cacheURL: URL) -> LoadedQuoteCache {
        guard let data = try? Data(contentsOf: cacheURL) else { return .empty }
        if var envelope = try? JSONDecoder().decode(QuoteCacheEnvelope.self, from: data),
           envelope.version == cacheVersion {
            envelope.normalize(maxRecentTexts: maxRecentTexts)
            return LoadedQuoteCache(envelope: envelope, migratedLegacySnapshot: false)
        }
        if let legacy = try? JSONDecoder().decode(QuoteSnapshot.self, from: data) {
            let envelope = QuoteCacheEnvelope(
                version: cacheVersion,
                latestChinese: legacy.language == "zh" ? legacy : nil,
                latestEnglish: legacy.language == "en" ? legacy : nil,
                recentTexts: [legacy.text]
            )
            return LoadedQuoteCache(envelope: envelope, migratedLegacySnapshot: true)
        }
        return .empty
    }

    private static func persist(_ envelope: QuoteCacheEnvelope, to cacheURL: URL) {
        guard let data = try? JSONEncoder().encode(envelope) else { return }
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

    private func withStateLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }

    private static func defaultCacheURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("AIClockBridge/quote-cache.json")
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func bodyTextAttributes(for language: String) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.alignment = .left
        return [
            .font: NSFont.systemFont(ofSize: language == "zh" ? 17 : 15, weight: .medium),
            .paragraphStyle: style,
        ]
    }

    private static func authorTextAttributes() -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byClipping
        style.alignment = .right
        return [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .paragraphStyle: style,
        ]
    }

    private static func renderQuotePage(_ quote: QuoteSnapshot) -> Data {
        let size = 240
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return Data(count: size * size * 2)
        }
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let titleStyle = NSMutableParagraphStyle()
        titleStyle.alignment = .center
        ("DAILY QUOTE" as NSString).draw(in: NSRect(x: 8, y: 215, width: 224, height: 18), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.systemTeal,
            .paragraphStyle: titleStyle,
        ])
        var bodyAttributes = bodyTextAttributes(for: quote.language)
        bodyAttributes[.foregroundColor] = NSColor.white
        ("“\(quote.text)”" as NSString).draw(in: bodyRect, withAttributes: bodyAttributes)
        var authorAttributes = authorTextAttributes()
        authorAttributes[.foregroundColor] = NSColor(white: 0.75, alpha: 1)
        ("— \(quote.author)" as NSString).draw(in: authorRect, withAttributes: authorAttributes)
        let footerStyle = NSMutableParagraphStyle()
        footerStyle.alignment = .left
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let footer = "\(quote.language.uppercased())  ·  \(formatter.string(from: quote.updatedAt))"
        (footer as NSString).draw(in: NSRect(x: 16, y: 15, width: 208, height: 16), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor(white: 0.48, alpha: 1),
            .paragraphStyle: footerStyle,
        ])
        NSGraphicsContext.restoreGraphicsState()

        guard let rendered = context.data else { return Data(count: size * size * 2) }
        let pixels = rendered.bindMemory(to: UInt8.self, capacity: size * size * 4)
        var output = Data(capacity: size * size * 2)
        for pixel in 0..<(size * size) {
            let offset = pixel * 4
            let value = (UInt16(pixels[offset] & 0xF8) << 8)
                | (UInt16(pixels[offset + 1] & 0xFC) << 3)
                | UInt16(pixels[offset + 2] >> 3)
            output.append(UInt8(value >> 8))
            output.append(UInt8(value & 0xFF))
        }
        return output
    }
}

private struct QuoteCacheEnvelope: Codable {
    var version: Int
    var latestChinese: QuoteSnapshot?
    var latestEnglish: QuoteSnapshot?
    var recentTexts: [String]

    enum CodingKeys: String, CodingKey {
        case version
        case latestChinese = "latest_chinese"
        case latestEnglish = "latest_english"
        case recentTexts = "recent_texts"
    }

    var currentSnapshot: QuoteSnapshot? {
        [latestChinese, latestEnglish].compactMap { $0 }.max {
            if $0.textRev != $1.textRev { return $0.textRev < $1.textRev }
            return $0.updatedAt < $1.updatedAt
        }
    }

    mutating func normalize(maxRecentTexts: Int) {
        var normalized: [String] = []
        for text in recentTexts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            normalized.removeAll { $0 == trimmed }
            normalized.append(trimmed)
        }
        if normalized.count > maxRecentTexts {
            normalized.removeFirst(normalized.count - maxRecentTexts)
        }
        recentTexts = normalized
    }
}

private struct LoadedQuoteCache {
    var envelope: QuoteCacheEnvelope
    var migratedLegacySnapshot: Bool

    static let empty = LoadedQuoteCache(
        envelope: QuoteCacheEnvelope(version: 1, latestChinese: nil,
                                     latestEnglish: nil, recentTexts: []),
        migratedLegacySnapshot: false
    )
}

private enum QuoteMonitorError: Error {
    case emptyResponse
    case notDisplayable
    case duplicate
}

private struct HitokotoResponse: Decodable {
    let text: String
    let source: String?
    let fromWho: String?

    enum CodingKeys: String, CodingKey {
        case text = "hitokoto"
        case source = "from"
        case fromWho = "from_who"
    }
}

private struct ZenQuoteResponse: Decodable {
    let text: String
    let author: String?

    enum CodingKeys: String, CodingKey {
        case text = "q"
        case author = "a"
    }
}
