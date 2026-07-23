import XCTest
@testable import CryptoTickerCore

final class ExchangeInfoTests: XCTestCase {

    private let json = """
    { "symbols": [
        { "symbol": "SOLUSDT", "status": "TRADING", "baseAsset": "SOL", "quoteAsset": "USDT" },
        { "symbol": "BTCUSDT", "status": "TRADING", "baseAsset": "BTC", "quoteAsset": "USDT" },
        { "symbol": "ETHBTC",  "status": "TRADING", "baseAsset": "ETH", "quoteAsset": "BTC"  },
        { "symbol": "LUNAUSDT","status": "BREAK",   "baseAsset": "LUNA","quoteAsset": "USDT" }
    ] }
    """.data(using: .utf8)!

    func testKeepsOnlyTradingUSDTPairs() {
        let result = ExchangeInfo.parse(json)
        XCTAssertEqual(result, [
            TradableSymbol(symbol: "solusdt", baseAsset: "SOL"),
            TradableSymbol(symbol: "btcusdt", baseAsset: "BTC"),
        ])
    }

    func testMalformedDataReturnsEmpty() {
        XCTAssertEqual(ExchangeInfo.parse(Data("not json".utf8)), [])
    }
}
