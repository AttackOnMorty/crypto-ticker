import XCTest
@testable import CryptoTickerCore

final class DayChartDataTests: XCTestCase {
    func testDecodesBinanceTradingDayTickerFields() throws {
        let data = Data(#"""
        {
          "symbol": "BTCUSDT",
          "priceChange": "-140.59",
          "priceChangePercent": "-0.219",
          "lastPrice": "63999.41",
          "openTime": 1784937600000
        }
        """#.utf8)

        let ticker = try JSONDecoder().decode(TradingDayTicker.self, from: data)
        XCTAssertEqual(ticker.lastPrice, "63999.41")
        XCTAssertEqual(ticker.priceChangePercent, "-0.219")
    }

    func testParsesOpenTimeAndCloseFromBinanceKlines() {
        let data = Data(#"""
        [
          [1721865600000, "65000", "65100", "64900", "65050.25", "12", 1721865899999, "0", 1, "0", "0", "0"],
          [1721865900000, "65050", "65200", "65000", "65180.50", "10", 1721866199999, "0", 1, "0", "0", "0"]
        ]
        """#.utf8)

        XCTAssertEqual(
            DayChartData.points(from: data),
            [
                DayChartPoint(openTime: 1_721_865_600_000, close: 65_050.25),
                DayChartPoint(openTime: 1_721_865_900_000, close: 65_180.50),
            ]
        )
    }

    func testRejectsMalformedOrNonFiniteClose() {
        XCTAssertNil(DayChartData.points(from: Data(#"[[1,"0","0","0","bad"]]"#.utf8)))
        XCTAssertNil(DayChartData.points(from: Data(#"[[1,"0","0","0","NaN"]]"#.utf8)))
        XCTAssertNil(DayChartData.points(from: Data("not json".utf8)))
    }

    func testUTCTradingDayAlwaysStartsAtMidnightUTC() {
        let date = Date(timeIntervalSince1970: 1_721_916_123)
        let start = DayChartData.utcDayStartMilliseconds(for: date)
        let expected = ISO8601DateFormatter().date(from: "2024-07-25T00:00:00Z")!

        XCTAssertEqual(start, Int64(expected.timeIntervalSince1970 * 1_000))
    }
}
