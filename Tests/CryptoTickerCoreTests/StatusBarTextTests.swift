import XCTest
@testable import CryptoTickerCore

final class StatusBarTextTests: XCTestCase {

    // MARK: connection indicator

    func testConnectedHasNoIndicator() {
        XCTAssertEqual(StatusBarText.indicator(for: .connected), "")
    }

    func testConnectingShowsHourglass() {
        XCTAssertEqual(StatusBarText.indicator(for: .connecting), "⏳")
    }

    func testDisconnectedErrorAndUnknownShowWarning() {
        XCTAssertEqual(StatusBarText.indicator(for: .disconnected), "⚠️")
        XCTAssertEqual(StatusBarText.indicator(for: .error(.invalidURL)), "⚠️")
        XCTAssertEqual(StatusBarText.indicator(for: nil), "⚠️")
    }

    // MARK: assembled title

    func testEmptySelectionShowsAppName() {
        XCTAssertEqual(StatusBarText.make(items: []), "CRYPTO TICKER")
    }

    func testEmptySelectionUsesCentralizedAppTitle() {
        // F5: the empty-state title comes from the single config constant, not an inline literal.
        XCTAssertEqual(StatusBarText.make(items: []), AppConfiguration.UI.appTitle)
    }

    func testSingleItemPreservesTrailingIndicatorSpacing() {
        XCTAssertEqual(
            StatusBarText.make(items: [.init(code: "BTC", price: "68,000", indicator: "")]),
            "BTC 68,000 "
        )
    }

    func testMultipleItemsJoinedWithSeparator() {
        let result = StatusBarText.make(items: [
            .init(code: "BTC", price: "68,000", indicator: ""),
            .init(code: "ETH", price: "2,500", indicator: "⚠️"),
        ])
        XCTAssertEqual(result, "BTC 68,000 | ETH 2,500 ⚠️")
    }
}
