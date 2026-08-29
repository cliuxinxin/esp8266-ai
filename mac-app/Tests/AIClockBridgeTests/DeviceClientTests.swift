import XCTest
@testable import AIClockBridge

final class DeviceClientTests: XCTestCase {
    func testParseInfoPreservesQuoteAndUnknownFutureModes() throws {
        let quote = Data(#"{"ip":"192.168.1.8","fw":"0.4.13","mode":"quote","effective":"quote","sprite_rev":3}"#.utf8)
        let future = Data(#"{"mode":"focus","effective":"focus","sprite_rev":4}"#.utf8)

        let quoteInfo = try XCTUnwrap(DeviceClient.parseInfo(quote))
        let futureInfo = try XCTUnwrap(DeviceClient.parseInfo(future))

        XCTAssertEqual(quoteInfo.mode, "quote")
        XCTAssertEqual(quoteInfo.effective, "quote")
        XCTAssertEqual(quoteInfo.firmwareVersion, "0.4.13")
        XCTAssertEqual(futureInfo.mode, "focus")
        XCTAssertEqual(futureInfo.effective, "focus")
    }

    func testAutoDisplayCapabilityUsesMinimumFirmwareVersion() {
        XCTAssertEqual(DeviceClient.supportsAutoDisplayConfiguration(firmwareVersion: "0.4.12"), false)
        XCTAssertEqual(DeviceClient.supportsAutoDisplayConfiguration(firmwareVersion: "0.4.13"), true)
        XCTAssertEqual(DeviceClient.supportsAutoDisplayConfiguration(firmwareVersion: "0.5.0"), true)
        XCTAssertEqual(DeviceClient.supportsAutoDisplayConfiguration(firmwareVersion: "v1.0.0"), true)
        XCTAssertNil(DeviceClient.supportsAutoDisplayConfiguration(firmwareVersion: "unknown"))
        XCTAssertNil(DeviceClient.supportsAutoDisplayConfiguration(firmwareVersion: ""))
    }

    func testDeviceDisplayNameRecognizesQuote() {
        var info = DeviceInfo()
        info.effective = "quote"

        XCTAssertEqual(MenuBarController.effectiveDisplayName(for: info), "名言")
    }
}
