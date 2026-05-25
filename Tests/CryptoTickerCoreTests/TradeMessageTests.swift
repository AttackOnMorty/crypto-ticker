import XCTest
@testable import CryptoTickerCore

/// Decoding only the price field from a @trade message (F8), instead of parsing every key
/// into a boxed dictionary per message.
final class TradeMessageTests: XCTestCase {

    func testExtractsPriceIgnoringOtherFields() {
        let json = #"{"e":"trade","E":1,"s":"BTCUSDT","t":2,"p":"68000.50","q":"0.1","T":3,"m":true,"M":true}"#
        XCTAssertEqual(TradeMessage.price(fromJSON: json), "68000.50")
    }

    func testReturnsNilWhenPriceMissing() {
        XCTAssertNil(TradeMessage.price(fromJSON: #"{"e":"trade","s":"BTCUSDT","q":"0.1"}"#))
    }

    func testReturnsNilForMalformedJSON() {
        XCTAssertNil(TradeMessage.price(fromJSON: "not json"))
        XCTAssertNil(TradeMessage.price(fromJSON: ""))
    }
}
