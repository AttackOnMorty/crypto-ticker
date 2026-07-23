import XCTest
@testable import CryptoTickerCore

final class SymbolSearchTests: XCTestCase {

    private let universe = [
        TradableSymbol(symbol: "solusdt",  baseAsset: "SOL"),
        TradableSymbol(symbol: "solousdt", baseAsset: "SOLO"),
        TradableSymbol(symbol: "dogusdt",  baseAsset: "DOG"),   // contains "O", not a prefix of "SOL"
        TradableSymbol(symbol: "btcusdt",  baseAsset: "BTC"),
    ]

    func testPrefixMatchesRankAboveSubstring() {
        let result = SymbolSearch.match(query: "sol", in: universe)
        XCTAssertEqual(result.map(\.symbol), ["solusdt", "solousdt"])
    }

    func testCaseInsensitive() {
        XCTAssertEqual(SymbolSearch.match(query: "BTC", in: universe).map(\.symbol), ["btcusdt"])
    }

    func testSubstringMatchIncluded() {
        // "og" is a substring of DOG's base but not a prefix.
        XCTAssertEqual(SymbolSearch.match(query: "og", in: universe).map(\.symbol), ["dogusdt"])
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertEqual(SymbolSearch.match(query: "   ", in: universe), [])
    }
}
