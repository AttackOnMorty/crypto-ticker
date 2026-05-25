import XCTest
@testable import CryptoTickerCore

final class SymbolValidationTests: XCTestCase {

    func testKeepsKnownSymbolsInOrder() {
        XCTAssertEqual(
            CryptoCurrency.validSymbols(from: ["btcusdt", "ethusdt"]),
            ["btcusdt", "ethusdt"]
        )
    }

    func testDropsUnknownSymbols() {
        // A tampered plist must not be able to inject an arbitrary URL segment.
        XCTAssertEqual(
            CryptoCurrency.validSymbols(from: ["btcusdt", "../evil@trade", "xrpusdt"]),
            ["btcusdt", "xrpusdt"]
        )
    }

    func testMatchIsCaseExact() {
        // The rest of the app compares symbols exactly; an off-case entry is unknown.
        XCTAssertEqual(CryptoCurrency.validSymbols(from: ["BTCUSDT"]), [])
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(CryptoCurrency.validSymbols(from: []), [])
    }
}
