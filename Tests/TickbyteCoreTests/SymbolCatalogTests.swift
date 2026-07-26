import XCTest
@testable import TickbyteCore

final class SymbolCatalogTests: XCTestCase {

    func testKeepsSupportedSymbolsInOrder() {
        XCTAssertEqual(SymbolCatalog.validSymbols(from: ["ethusdt", "btcusdt"]), ["ethusdt", "btcusdt"])
    }

    func testDropsUnsupportedAndInjectionInput() {
        // The symbol is interpolated unescaped into the WebSocket path — anything not on
        // the whitelist must be dropped outright, not merely sanitized.
        XCTAssertEqual(SymbolCatalog.validSymbols(from: ["../evil@trade", "btcusdt"]), ["btcusdt"])
        XCTAssertEqual(SymbolCatalog.validSymbols(from: ["solusdt", "ethusdt"]), ["ethusdt"])
    }

    func testRejectsOffCaseSymbols() {
        XCTAssertEqual(SymbolCatalog.validSymbols(from: ["BTCUSDT"]), [])
    }

    func testDropsDuplicates() {
        XCTAssertEqual(SymbolCatalog.validSymbols(from: ["btcusdt", "ethusdt", "btcusdt"]), ["btcusdt", "ethusdt"])
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(SymbolCatalog.validSymbols(from: []), [])
    }

    func testDisplayCodeStripsQuoteAndUppercases() {
        XCTAssertEqual(SymbolCatalog.displayCode(for: "btcusdt"), "BTC")
        XCTAssertEqual(SymbolCatalog.displayCode(for: "ethusdt"), "ETH")
    }
}
