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

    func testSelectedSymbolReportsItsSocketState() {
        XCTAssertEqual(PanelText.status(isSelected: true, state: .connected), .live)
        XCTAssertEqual(PanelText.status(isSelected: true, state: .connecting), .sync)
        XCTAssertEqual(PanelText.status(isSelected: true, state: .disconnected), .lost)
        XCTAssertEqual(PanelText.status(isSelected: true, state: .error(.invalidURL)), .lost)
        XCTAssertEqual(PanelText.status(isSelected: true, state: nil), .lost)
    }

    func testDeselectedSymbolIsIdleNotLost() {
        // A coin switched off the menu bar has no socket by design — reporting it as a
        // failure would be a lie.
        XCTAssertEqual(PanelText.status(isSelected: false, state: nil), .idle)
        XCTAssertEqual(PanelText.status(isSelected: false, state: .connected), .idle)
    }

    func testStatusLabelsAreTheSameWidthSoTheHeaderNeverReflows() {
        let widths = Set([PanelText.Status.live, .sync, .lost, .idle].map(\.rawValue.count))
        XCTAssertEqual(widths, [4])
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
