import XCTest
@testable import CryptoTickerCore

final class SymbolFormatTests: XCTestCase {

    func testAcceptsWellFormedUSDTSymbols() {
        XCTAssertTrue(SymbolFormat.isValid("btcusdt"))
        XCTAssertTrue(SymbolFormat.isValid("solusdt"))
        XCTAssertTrue(SymbolFormat.isValid("1inchusdt"))
    }

    func testRejectsInjectionAndMalformed() {
        // The symbol is interpolated unescaped into the WebSocket path.
        XCTAssertFalse(SymbolFormat.isValid("../evil@trade"))
        XCTAssertFalse(SymbolFormat.isValid("BTCUSDT"))   // uppercase
        XCTAssertFalse(SymbolFormat.isValid("usdt"))       // no base asset
        XCTAssertFalse(SymbolFormat.isValid(""))
        XCTAssertFalse(SymbolFormat.isValid("btcusd"))     // wrong quote
        XCTAssertFalse(SymbolFormat.isValid(String(repeating: "a", count: 30) + "usdt")) // overlong base
    }

    func testDisplayCodeStripsQuoteAndUppercases() {
        XCTAssertEqual(SymbolFormat.displayCode(for: "solusdt"), "SOL")
        XCTAssertEqual(SymbolFormat.displayCode(for: "btcusdt"), "BTC")
        XCTAssertEqual(SymbolFormat.displayCode(for: "1inchusdt"), "1INCH")
    }
}
