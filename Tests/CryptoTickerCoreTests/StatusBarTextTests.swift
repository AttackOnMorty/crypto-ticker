import XCTest
@testable import CryptoTickerCore

final class StatusBarTextTests: XCTestCase {

    private func substring(_ title: StatusBarText.Title, _ range: NSRange) -> String {
        (title.text as NSString).substring(with: range)
    }

    // MARK: empty state

    func testEmptySelectionShowsLoadingText() {
        let title = StatusBarText.make(items: [])
        XCTAssertEqual(title.text, AppConfiguration.UI.loadingText)
    }

    func testEmptySelectionIsDimmedWhole() {
        // Nothing to report reads as system text, not as live data.
        let title = StatusBarText.make(items: [])
        XCTAssertTrue(title.codeRanges.isEmpty)
        XCTAssertTrue(title.valueRanges.isEmpty)
        XCTAssertEqual(title.staleRanges, [NSRange(location: 0, length: (title.text as NSString).length)])
    }

    // MARK: assembled title

    func testSingleLiveItemJoinsCodeAndPrice() {
        let title = StatusBarText.make(items: [.init(code: "BTC", price: "68,000", isLive: true)])
        XCTAssertEqual(title.text, "BTC 68,000")
    }

    func testMultipleItemsSeparatedBySpacingNotAGlyph() {
        let title = StatusBarText.make(items: [
            .init(code: "BTC", price: "68,000", isLive: true),
            .init(code: "ETH", price: "2,500", isLive: true),
        ])
        XCTAssertEqual(title.text, "BTC 68,000   ETH 2,500")
    }

    // MARK: colour ranges

    func testLiveItemSplitsCodeFromValue() {
        let title = StatusBarText.make(items: [.init(code: "BTC", price: "68,000", isLive: true)])
        XCTAssertEqual(title.codeRanges.map { substring(title, $0) }, ["BTC"])
        XCTAssertEqual(title.valueRanges.map { substring(title, $0) }, ["68,000"])
        XCTAssertTrue(title.staleRanges.isEmpty)
    }

    func testStaleItemIsDimmedWholeRatherThanFlagged() {
        // No warning glyph: the whole item dims instead, so the title never changes width
        // when a socket drops.
        let title = StatusBarText.make(items: [.init(code: "BTC", price: "68,000", isLive: false)])
        XCTAssertEqual(title.text, "BTC 68,000")
        XCTAssertEqual(title.staleRanges.map { substring(title, $0) }, ["BTC 68,000"])
        XCTAssertTrue(title.codeRanges.isEmpty)
        XCTAssertTrue(title.valueRanges.isEmpty)
    }

    func testMixedItemsColourIndependently() {
        let title = StatusBarText.make(items: [
            .init(code: "BTC", price: "68,000", isLive: false),
            .init(code: "ETH", price: "2,500", isLive: true),
        ])
        XCTAssertEqual(title.staleRanges.map { substring(title, $0) }, ["BTC 68,000"])
        XCTAssertEqual(title.codeRanges.map { substring(title, $0) }, ["ETH"])
        XCTAssertEqual(title.valueRanges.map { substring(title, $0) }, ["2,500"])
    }

    // MARK: change detection

    func testTitleIsEquatableSoStalenessChangesAreDetected() {
        // Same text, different colouring — a plain string compare would skip the update.
        let live = StatusBarText.make(items: [.init(code: "BTC", price: "68,000", isLive: true)])
        let stale = StatusBarText.make(items: [.init(code: "BTC", price: "68,000", isLive: false)])
        XCTAssertEqual(live.text, stale.text)
        XCTAssertNotEqual(live, stale)
    }
}
