import XCTest
@testable import AIClockBridge

private actor StubQuoteClient: QuoteHTTPClient {
    private var responses: [String: [Result<Data, Error>]]
    private(set) var requestedHosts: [String] = []
    private(set) var requestedURLs: [URL] = []

    init(responses: [String: [Result<Data, Error>]]) {
        self.responses = responses
    }

    func data(from url: URL) async throws -> Data {
        let host = url.host ?? ""
        requestedHosts.append(host)
        requestedURLs.append(url)
        guard var queue = responses[host], !queue.isEmpty else {
            throw URLError(.cannotFindHost)
        }
        let result = queue.removeFirst()
        responses[host] = queue
        return try result.get()
    }

    func hosts() -> [String] { requestedHosts }
    func urls() -> [URL] { requestedURLs }
}

final class QuoteMonitorTests: XCTestCase {
    private func snapshot(text: String, author: String, language: String,
                          revision: Int = 1) -> QuoteSnapshot {
        QuoteSnapshot(text: text, author: author, language: language,
                      updatedAt: Date(timeIntervalSince1970: 1_000), textRev: revision)
    }

    func testParsesHitokoto() throws {
        let zh = Data(#"{"hitokoto":"知者不惑。","from":"论语","from_who":"孔子"}"#.utf8)

        XCTAssertEqual(try QuoteMonitor.parseHitokoto(zh).author, "孔子")
    }

    func testRejectsEnglishQuote() throws {
        let english = Data(#"{"hitokoto":"Stay hungry, stay foolish.","from":"Motivational","from_who":"Steve Jobs"}"#.utf8)

        XCTAssertThrowsError(try QuoteMonitor.parseHitokoto(english))
    }

    func testAuthorFallsBackToSourceThenAnonymous() throws {
        let sourceOnly = Data(#"{"hitokoto":"山高水长","from":"古语","from_who":null}"#.utf8)
        let anonymousChinese = Data(#"{"hitokoto":"山高水长","from":null,"from_who":null}"#.utf8)

        XCTAssertEqual(try QuoteMonitor.parseHitokoto(sourceOnly).author, "古语")
        XCTAssertEqual(try QuoteMonitor.parseHitokoto(anonymousChinese).author, "佚名")
    }

    func testLayoutValidationRejectsLongCJKAndEnglishAuthorsBeforeTheyCanClip() {
        let longChineseAuthor = snapshot(
            text: "知者不惑。",
            author: "中国古代一位名字和出处都特别特别长的思想家与教育家",
            language: "zh"
        )
        let longEnglishAuthor = snapshot(
            text: "Stay curious.",
            author: "An Exceptionally Long Author Name That Cannot Fit In The Attribution Row",
            language: "en"
        )

        XCTAssertFalse(QuoteMonitor.isDisplayable(longChineseAuthor))
        XCTAssertFalse(QuoteMonitor.isDisplayable(longEnglishAuthor))
    }

    func testLayoutValidationRejectsBodyThatOverflowsItsRenderedRectangle() {
        let quote = snapshot(
            text: String(repeating: "W", count: 170),
            author: "Author",
            language: "en"
        )

        XCTAssertLessThanOrEqual(quote.text.count, 180)
        XCTAssertFalse(QuoteMonitor.isDisplayable(quote))
    }

    func testRefreshRejectsDuplicatesAndRetainsCachedSnapshotAfterFailure() async throws {
        let zh = Data(#"{"hitokoto":"知者不惑。","from":"论语","from_who":"孔子"}"#.utf8)
        let duplicate = Data(#"{"hitokoto":"知者不惑。","from":"论语","from_who":"孔子"}"#.utf8)
        let fresh = Data(#"{"hitokoto":"山高水长","from":"古语","from_who":null}"#.utf8)
        let client = StubQuoteClient(responses: [
            "v1.hitokoto.cn": [.success(zh), .success(duplicate), .success(fresh),
                                .failure(URLError(.timedOut)), .failure(URLError(.timedOut)),
                                .failure(URLError(.timedOut))],
        ])
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let updated = Date(timeIntervalSince1970: 1_000)
        var now = updated
        let monitor = QuoteMonitor(client: client, cacheURL: cache, now: { now }, staleAfter: 60,
                                   errorReporter: { _ in })

        await monitor.refresh(force: true)
        XCTAssertEqual(monitor.snapshot?.language, "zh")
        let firstHosts = await client.hosts()
        XCTAssertEqual(firstHosts, ["v1.hitokoto.cn"])

        await monitor.refresh(force: true)
        XCTAssertEqual(monitor.snapshot?.text, "山高水长")
        let secondHosts = await client.hosts()
        XCTAssertEqual(secondHosts, ["v1.hitokoto.cn", "v1.hitokoto.cn", "v1.hitokoto.cn"])

        now = updated.addingTimeInterval(61)
        await monitor.refresh(force: true)
        XCTAssertEqual(monitor.snapshot?.text, "山高水长")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: monitor.jsonData()) as? [String: Any])
        XCTAssertEqual(object["stale"] as? Bool, true)
    }

    func testTextRGB565HasFixed240SquareWireSize() async throws {
        let zh = Data(#"{"hitokoto":"知者不惑。","from":"论语","from_who":"孔子"}"#.utf8)
        let client = StubQuoteClient(responses: ["v1.hitokoto.cn": [.success(zh)]])
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let monitor = QuoteMonitor(client: client, cacheURL: cache, errorReporter: { _ in })

        await monitor.refresh(force: true)
        XCTAssertEqual(monitor.textRGB565().count, 240 * 240 * 2)
    }

    func testRefreshRequestsOnlyChineseProviderEvenAfterChineseSnapshot() async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let cached = snapshot(text: "知者不惑。", author: "孔子", language: "zh", revision: 7)
        try JSONEncoder().encode(cached).write(to: cache)
        let freshChinese = Data(#"{"hitokoto":"山高水长","from":"古语","from_who":null}"#.utf8)
        let english = Data(#"[{"q":"Stay hungry, stay foolish.","a":"Steve Jobs"}]"#.utf8)
        let client = StubQuoteClient(responses: [
            "v1.hitokoto.cn": [.success(freshChinese)],
            "zenquotes.io": [.success(english)],
        ])
        let monitor = QuoteMonitor(client: client, cacheURL: cache, errorReporter: { _ in })

        await monitor.refresh(force: true)

        XCTAssertEqual(monitor.snapshot?.text, "山高水长")
        XCTAssertEqual(monitor.snapshot?.language, "zh")
        let hosts = await client.hosts()
        XCTAssertEqual(hosts, ["v1.hitokoto.cn"])
    }

    func testRefreshRequestsAllSelectedChineseCategoriesWithinScreenLength() async throws {
        let chinese = Data(#"{"hitokoto":"山高水长","from":"古语","from_who":null}"#.utf8)
        let client = StubQuoteClient(responses: ["v1.hitokoto.cn": [.success(chinese)]])
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let monitor = QuoteMonitor(client: client, cacheURL: cache, errorReporter: { _ in })

        await monitor.refresh(force: true)

        let urls = await client.urls()
        let url = try XCTUnwrap(urls.first)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        XCTAssertEqual(items.filter { $0.name == "c" }.compactMap(\.value),
                       ["d", "k", "i", "e", "g", "h"])
        XCTAssertEqual(items.first { $0.name == "max_length" }?.value, "45")
        XCTAssertEqual(items.first { $0.name == "encode" }?.value, "json")
    }

    func testEnglishOnlyCacheIsNotRestored() throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let english = snapshot(text: "Stay hungry, stay foolish.", author: "Steve Jobs",
                               language: "en", revision: 8)
        let envelope: [String: Any] = [
            "version": 1,
            "latest_english": try JSONSerialization.jsonObject(with: JSONEncoder().encode(english)),
            "recent_texts": [english.text],
        ]
        try JSONSerialization.data(withJSONObject: envelope).write(to: cache)

        let monitor = QuoteMonitor(client: StubQuoteClient(responses: [:]), cacheURL: cache,
                                   errorReporter: { _ in })

        XCTAssertNil(monitor.snapshot)
        XCTAssertTrue(monitor.textRGB565().isEmpty)
    }

    func testVersionedCachePreservesChineseAndRecentHistoryAcrossRestart() async throws {
        let firstChinese = Data(#"{"hitokoto":"知者不惑。","from":"论语","from_who":"孔子"}"#.utf8)
        let freshChinese = Data(#"{"hitokoto":"山高水长","from":"古语","from_who":null}"#.utf8)
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let firstClient = StubQuoteClient(responses: [
            "v1.hitokoto.cn": [.success(firstChinese), .success(freshChinese)],
        ])
        let firstMonitor = QuoteMonitor(client: firstClient, cacheURL: cache, errorReporter: { _ in })

        await firstMonitor.refresh(force: true)
        await firstMonitor.refresh(force: true)

        let envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: cache)) as? [String: Any]
        )
        XCTAssertEqual(envelope["version"] as? Int, 1)
        XCTAssertEqual((envelope["latest_chinese"] as? [String: Any])?["text"] as? String, "山高水长")
        XCTAssertEqual(envelope["recent_texts"] as? [String],
                       ["知者不惑。", "山高水长"])

        let restartedClient = StubQuoteClient(responses: [:])
        let restarted = QuoteMonitor(client: restartedClient, cacheURL: cache, errorReporter: { _ in })
        XCTAssertEqual(restarted.snapshot?.text, "山高水长")
    }

    func testLegacySingleSnapshotCacheMigratesToVersionedEnvelope() throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let legacy = snapshot(text: "知者不惑。", author: "孔子", language: "zh", revision: 7)
        try JSONEncoder().encode(legacy).write(to: cache)

        let monitor = QuoteMonitor(client: StubQuoteClient(responses: [:]), cacheURL: cache,
                                   errorReporter: { _ in })

        XCTAssertEqual(monitor.snapshot, legacy)
        let migrated = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: cache)) as? [String: Any]
        )
        XCTAssertEqual(migrated["version"] as? Int, 1)
        XCTAssertEqual((migrated["latest_chinese"] as? [String: Any])?["text"] as? String,
                       legacy.text)
        XCTAssertEqual(migrated["recent_texts"] as? [String], [legacy.text])
    }
}
