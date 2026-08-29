import XCTest
@testable import AIClockBridge

private actor StubQuoteClient: QuoteHTTPClient {
    private var responses: [String: [Result<Data, Error>]]
    private(set) var requestedHosts: [String] = []

    init(responses: [String: [Result<Data, Error>]]) {
        self.responses = responses
    }

    func data(from url: URL) async throws -> Data {
        let host = url.host ?? ""
        requestedHosts.append(host)
        guard var queue = responses[host], !queue.isEmpty else {
            throw URLError(.cannotFindHost)
        }
        let result = queue.removeFirst()
        responses[host] = queue
        return try result.get()
    }

    func hosts() -> [String] { requestedHosts }
}

final class QuoteMonitorTests: XCTestCase {
    func testParsesHitokotoAndZenQuotes() throws {
        let zh = Data(#"{"hitokoto":"知者不惑。","from":"论语","from_who":"孔子"}"#.utf8)
        let en = Data(#"[{"q":"Stay hungry, stay foolish.","a":"Steve Jobs"}]"#.utf8)

        XCTAssertEqual(try QuoteMonitor.parseHitokoto(zh).author, "孔子")
        XCTAssertEqual(try QuoteMonitor.parseZenQuotes(en).text, "Stay hungry, stay foolish.")
    }

    func testAuthorFallsBackToSourceThenAnonymous() throws {
        let sourceOnly = Data(#"{"hitokoto":"山高水长","from":"古语","from_who":null}"#.utf8)
        let anonymousChinese = Data(#"{"hitokoto":"山高水长","from":null,"from_who":null}"#.utf8)
        let noAuthor = Data(#"[{"q":"A quote","a":""}]"#.utf8)

        XCTAssertEqual(try QuoteMonitor.parseHitokoto(sourceOnly).author, "古语")
        XCTAssertEqual(try QuoteMonitor.parseHitokoto(anonymousChinese).author, "佚名")
        XCTAssertEqual(try QuoteMonitor.parseZenQuotes(noAuthor).author, "Anonymous")
    }

    func testChineseProviderFailureFallsBackToEnglishProvider() async throws {
        let en = Data(#"[{"q":"Stay hungry, stay foolish.","a":"Steve Jobs"}]"#.utf8)
        let client = StubQuoteClient(responses: [
            "v1.hitokoto.cn": [.failure(URLError(.timedOut))],
            "zenquotes.io": [.success(en)],
        ])
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let monitor = QuoteMonitor(client: client, cacheURL: cache, errorReporter: { _ in })

        await monitor.refresh(force: true)

        XCTAssertEqual(monitor.snapshot?.language, "en")
        let hosts = await client.hosts()
        XCTAssertEqual(hosts, ["v1.hitokoto.cn", "zenquotes.io"])
    }

    func testEnglishProviderFailureFallsBackToChineseProvider() async throws {
        let firstChinese = Data(#"{"hitokoto":"知者不惑。","from":"论语","from_who":"孔子"}"#.utf8)
        let fallbackChinese = Data(#"{"hitokoto":"山高水长","from":"古语","from_who":null}"#.utf8)
        let client = StubQuoteClient(responses: [
            "v1.hitokoto.cn": [.success(firstChinese), .success(fallbackChinese)],
            "zenquotes.io": [.failure(URLError(.timedOut))],
        ])
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let monitor = QuoteMonitor(client: client, cacheURL: cache, errorReporter: { _ in })

        await monitor.refresh(force: true)
        await monitor.refresh(force: true)

        XCTAssertEqual(monitor.snapshot?.text, "山高水长")
        let hosts = await client.hosts()
        XCTAssertEqual(hosts, ["v1.hitokoto.cn", "zenquotes.io", "v1.hitokoto.cn"])
    }

    func testRefreshAlternatesProvidersRejectsDuplicatesAndRetainsCachedSnapshotAfterFailure() async throws {
        let zh = Data(#"{"hitokoto":"知者不惑。","from":"论语","from_who":"孔子"}"#.utf8)
        let enDuplicate = Data(#"[{"q":"知者不惑。","a":"Anonymous"}]"#.utf8)
        let en = Data(#"[{"q":"Stay hungry, stay foolish.","a":"Steve Jobs"}]"#.utf8)
        let client = StubQuoteClient(responses: [
            "v1.hitokoto.cn": [.success(zh)],
            "zenquotes.io": [.success(enDuplicate), .success(en), .failure(URLError(.timedOut))],
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
        XCTAssertEqual(monitor.snapshot?.text, "Stay hungry, stay foolish.")
        let secondHosts = await client.hosts()
        XCTAssertEqual(secondHosts, ["v1.hitokoto.cn", "zenquotes.io", "v1.hitokoto.cn", "zenquotes.io"])

        now = updated.addingTimeInterval(61)
        await monitor.refresh(force: true)
        XCTAssertEqual(monitor.snapshot?.text, "Stay hungry, stay foolish.")
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
}
