import XCTest
@testable import TickbyteCore

/// Locks the wire-compatible raw values so the typed constants stay in sync with any
/// external observers and so a rename is a compile error, not a silent break.
final class NotificationNameTests: XCTestCase {
    func testPriceUpdatedRawValue() {
        XCTAssertEqual(Notification.Name.priceUpdated.rawValue, "PriceUpdated")
    }

    func testConnectionStateChangedRawValue() {
        XCTAssertEqual(Notification.Name.connectionStateChanged.rawValue, "ConnectionStateChanged")
    }
}
