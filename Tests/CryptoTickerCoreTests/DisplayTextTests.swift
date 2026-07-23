import XCTest
@testable import CryptoTickerCore

final class DisplayTextTests: XCTestCase {

    func testMenuRowUsesCodeOnly() {
        let row = MenuRowText.make(glyph: "●", code: "SOL", price: "77.58", change: "+0.13%")
        XCTAssertEqual(row.text, "●\tSOL\t$77.58\t+0.13%")
        XCTAssertEqual(row.statusRange, NSRange(location: 0, length: 1))
        XCTAssertEqual(row.changeRange, NSRange(location: (row.text as NSString).length - 6, length: 6))
    }

    func testStatusBarJoinsCodePriceIndicator() {
        let text = StatusBarText.make(items: [
            .init(code: "BTC", price: "63,201", indicator: ""),
            .init(code: "ETH", price: "3,410", indicator: "⚠️"),
        ])
        XCTAssertEqual(text, "BTC 63,201 | ETH 3,410 ⚠️")
    }

    func testStatusBarEmptyIsAppTitle() {
        XCTAssertEqual(StatusBarText.make(items: []), AppConfiguration.UI.appTitle)
    }
}
