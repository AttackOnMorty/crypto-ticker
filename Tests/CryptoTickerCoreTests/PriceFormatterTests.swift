import XCTest
@testable import CryptoTickerCore

final class PriceFormatterTests: XCTestCase {

    // MARK: price — magnitude buckets (F7/F16 single source)

    func testPriceAtOrAbove1000HasNoDecimalsAndGrouping() {
        XCTAssertEqual(PriceFormatter.price("68000.4"), "68,000")
        XCTAssertEqual(PriceFormatter.price("1500"), "1,500")
    }

    func testPriceBetween1And1000HasTwoDecimals() {
        XCTAssertEqual(PriceFormatter.price("42.5"), "42.50")
        XCTAssertEqual(PriceFormatter.price("3"), "3.00")
    }

    func testPriceBelow1HasFourDecimals() {
        XCTAssertEqual(PriceFormatter.price("0.5"), "0.5000")
        XCTAssertEqual(PriceFormatter.price("0.1234"), "0.1234")
    }

    // MARK: price — unparseable -> placeholder (F11, not the raw string)

    func testPriceUnparseableReturnsPlaceholderNotRawString() {
        XCTAssertEqual(PriceFormatter.price("not-a-number"), PriceFormatter.placeholder)
        XCTAssertEqual(PriceFormatter.price(""), PriceFormatter.placeholder)
    }

    func testPlaceholderIsNotInjectionOfRemoteText() {
        // A hostile feed value must never appear verbatim in the UI.
        XCTAssertEqual(PriceFormatter.price("<script>"), PriceFormatter.placeholder)
    }

    // MARK: price/percent — non-finite feed values -> placeholder (F1)

    func testPriceNonFiniteReturnsPlaceholder() {
        // Double("inf"/"nan"/"1e400") parses successfully to a non-finite value;
        // it must not render as "+∞"/"NaN" in the UI.
        XCTAssertEqual(PriceFormatter.price("inf"), PriceFormatter.placeholder)
        XCTAssertEqual(PriceFormatter.price("Infinity"), PriceFormatter.placeholder)
        XCTAssertEqual(PriceFormatter.price("-inf"), PriceFormatter.placeholder)
        XCTAssertEqual(PriceFormatter.price("nan"), PriceFormatter.placeholder)
        XCTAssertEqual(PriceFormatter.price("1e400"), PriceFormatter.placeholder)
    }

    func testPercentNonFiniteReturnsPlaceholder() {
        XCTAssertEqual(PriceFormatter.percent("inf"), PriceFormatter.placeholder)
        XCTAssertEqual(PriceFormatter.percent("nan"), PriceFormatter.placeholder)
    }

    func testPercentValueNilWhenNonFinite() {
        // The colour decision must not receive NaN (NaN >= 0 is false -> spurious red).
        XCTAssertNil(PriceFormatter.percentValue("nan"))
        XCTAssertNil(PriceFormatter.percentValue("inf"))
    }

    // MARK: percent — signed, two decimals, trailing % (F16 single source)

    func testPercentIsSignedTwoDecimalsWithPercentSign() {
        XCTAssertEqual(PriceFormatter.percent("2.5"), "+2.50%")
        XCTAssertEqual(PriceFormatter.percent("-1.23"), "-1.23%")
        XCTAssertEqual(PriceFormatter.percent("0"), "+0.00%")
    }

    func testPercentUnparseableReturnsPlaceholder() {
        XCTAssertEqual(PriceFormatter.percent("xyz"), PriceFormatter.placeholder)
    }

    // MARK: percentValue — numeric for colouring, parsed from the RAW number (no round-trip)

    func testPercentValueParsesRawNumber() {
        XCTAssertEqual(PriceFormatter.percentValue("2.5"), 2.5)
        XCTAssertEqual(PriceFormatter.percentValue("-1"), -1)
    }

    func testPercentValueNilWhenUnparseable() {
        XCTAssertNil(PriceFormatter.percentValue("xyz"))
    }
}
