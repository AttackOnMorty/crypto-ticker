import XCTest
@testable import CryptoTickerCore

/// The attributed menu-row text plus explicit ranges, so colouring never relies on
/// searching for a token that can collide with the placeholder "—" (F3).
final class MenuRowTextTests: XCTestCase {

    func testAssemblesExpectedText() {
        let row = MenuRowText.make(glyph: "●", code: "BTC", price: "68,000", change: "+2.50%")
        XCTAssertEqual(row.text, "●\tBTC\t$68,000\t+2.50%")
    }

    func testStatusRangeIsLeadingGlyph() {
        let row = MenuRowText.make(glyph: "○", code: "ETH", price: "2,500", change: "-1.20%")
        XCTAssertEqual((row.text as NSString).substring(with: row.statusRange), "○")
        XCTAssertEqual(row.statusRange.location, 0)
    }

    func testChangeRangeIsTheTrailingChangeToken() {
        let row = MenuRowText.make(glyph: "●", code: "BTC", price: "68,000", change: "+2.50%")
        XCTAssertEqual((row.text as NSString).substring(with: row.changeRange), "+2.50%")
    }

    func testChangeRangePointsAtChangeEvenWhenPriceIsAlsoPlaceholder() {
        // The bug: range(of: "—") matched the price's dash. The explicit range must point
        // at the trailing change token, not the first "—".
        let row = MenuRowText.make(glyph: "●", code: "BTC", price: "—", change: "—")
        XCTAssertEqual((row.text as NSString).substring(with: row.changeRange), "—")
        let ns = row.text as NSString
        XCTAssertEqual(row.changeRange.location, ns.length - 1) // the LAST dash, not the price's
    }
}
