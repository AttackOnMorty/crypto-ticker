import XCTest
@testable import CryptoTickerCore

final class PanelTextTests: XCTestCase {

    // MARK: pair

    func testPairSpellsOutTheQuoteAsset() {
        XCTAssertEqual(PanelText.pair(for: "btcusdt"), "BTC/USDT")
    }

    func testPairFallsBackToTheBareCode() {
        XCTAssertEqual(PanelText.pair(for: "btc"), "BTC")
    }

    // MARK: status

    func testSymbolReportsItsSocketState() {
        XCTAssertEqual(PanelText.status(state: .connected), .live)
        XCTAssertEqual(PanelText.status(state: .connecting), .sync)
        XCTAssertEqual(PanelText.status(state: .disconnected), .lost)
        XCTAssertEqual(PanelText.status(state: .error(.invalidURL)), .lost)
        XCTAssertEqual(PanelText.status(state: nil), .lost)
    }

    func testStatusLabelsAreTheSameWidthSoTheHeaderNeverReflows() {
        let widths = Set([PanelText.Status.live, .sync, .lost].map(\.rawValue.count))
        XCTAssertEqual(widths, [4])
    }

    func testSharedFeedIsLiveOnlyWhenEverySocketIsLive() {
        XCTAssertEqual(PanelText.feedStatus(states: [.connected, .connected]), .live)
        XCTAssertEqual(PanelText.feedStatus(states: [.connected, .connecting]), .sync)
        XCTAssertEqual(PanelText.feedStatus(states: [.connected, .disconnected]), .lost)
        XCTAssertEqual(PanelText.feedStatus(states: []), .lost)
    }

    func testFreshnessUsesCompactTechnicalUnits() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertEqual(PanelText.freshness(updatedAt: nil, now: now), "UPDATED --")
        XCTAssertEqual(
            PanelText.freshness(updatedAt: now.addingTimeInterval(-4), now: now),
            "UPDATED 04S AGO"
        )
        XCTAssertEqual(
            PanelText.freshness(updatedAt: now.addingTimeInterval(-125), now: now),
            "UPDATED 02M AGO"
        )
    }

    // MARK: change

    func testChangeCarriesDirectionInSignAndCase() {
        XCTAssertEqual(PanelText.change(fromRaw: "2.5").text, "+2.50%")
        XCTAssertEqual(PanelText.change(fromRaw: "2.5").direction, .up)
        XCTAssertEqual(PanelText.change(fromRaw: "-1.2").text, "-1.20%")
        XCTAssertEqual(PanelText.change(fromRaw: "-1.2").direction, .down)
    }

    func testZeroChangeCountsAsUp() {
        XCTAssertEqual(PanelText.change(fromRaw: "0").direction, .up)
    }

    func testUnparseableChangeFallsBackToThePlaceholder() {
        let change = PanelText.change(fromRaw: "not a number")
        XCTAssertEqual(change.text, PriceFormatter.placeholder)
        XCTAssertEqual(change.direction, .flat)
    }
}
