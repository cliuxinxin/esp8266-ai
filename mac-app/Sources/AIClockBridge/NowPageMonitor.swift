import AppKit
import Foundation

/// Builds the composite "NOW" (此刻) page for both the device bitmap
/// (/now/text.raw) and the menu-bar mirror. The quote, weather and Codex
/// numbers all come from monitors that already exist in the bridge — this
/// monitor only merges their latest snapshots into one 240×240 frame and
/// re-renders when any of them changes (quote text rev / weather rev / Codex
/// pct & reset minutes). The firmware polls /now for the {rev} and refetches
/// /now/text.raw only when the rev moves, exactly like the quote page.
final class NowPageMonitor {
    static let layoutRevision = 2

    /// Cheap tick: re-rendering is skipped unless the computed rev changed, and
    /// a full render is only ~115 KB of RGB565 over the LAN, so 10s keeps the
    /// quote/weather/Codex rows fresh without hammering the bridge.
    private static let refreshInterval: TimeInterval = 10

    private let quoteMonitor: QuoteMonitor
    private let weatherMonitor: WeatherMonitor
    private let codexUsageProvider: () -> ProviderUsage
    private let nowProvider: () -> Date
    private let lock = NSLock()
    private var storedData: NowPageData?
    private var storedRev = -1
    private var storedText = Data()
    private var timer: Timer?

    init(quoteMonitor: QuoteMonitor, weatherMonitor: WeatherMonitor,
         codexUsageProvider: @escaping () -> ProviderUsage,
         now: @escaping () -> Date = Date.init) {
        self.quoteMonitor = quoteMonitor
        self.weatherMonitor = weatherMonitor
        self.codexUsageProvider = codexUsageProvider
        self.nowProvider = now
        refresh()
    }

    var snapshot: NowPageData? {
        withStateLock { storedData }
    }

    /// /now metadata — a tiny JSON the firmware polls to decide when to refetch
    /// the bitmap: `{"rev": N, "available": true}`.
    func jsonData() -> Data {
        withStateLock {
            Self.metadataJSON(revision: storedRev, available: storedData != nil)
        }
    }

    static func metadataJSON(revision: Int, available: Bool) -> Data {
        guard available else { return Data("{\"available\":false}".utf8) }
        let object: [String: Any] = [
            "rev": revision,
            "layout_rev": layoutRevision,
            "available": true,
        ]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    }

    /// The 240×240 RGB565 frame for the ESP8266 (/now/text.raw).
    func textRGB565() -> Data {
        withStateLock { storedText }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        let data = NowPageData(quote: quoteMonitor.snapshot,
                               weather: weatherMonitor.snapshot,
                               codex: codexUsageProvider(),
                               now: nowProvider())
        let newRev = NowPageLayout.rev(for: data)
        withStateLock {
            guard newRev != storedRev else { return }
            storedRev = newRev
            storedData = data
            storedText = NowPageLayout.renderRGB565(data)
        }
    }

    private func withStateLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }
}
