import XCTest
@testable import CryptoTickerCore

/// Exponential reconnect backoff with a cap (F2): base 5s, doubling, capped at 60s.
final class BackoffPolicyTests: XCTestCase {

    func testFirstAttemptIsBaseDelay() {
        XCTAssertEqual(BackoffPolicy.delay(attempt: 0), 5)
    }

    func testDelayDoubles() {
        XCTAssertEqual(BackoffPolicy.delay(attempt: 1), 10)
        XCTAssertEqual(BackoffPolicy.delay(attempt: 2), 20)
        XCTAssertEqual(BackoffPolicy.delay(attempt: 3), 40)
    }

    func testDelayIsCapped() {
        XCTAssertEqual(BackoffPolicy.delay(attempt: 4), 60)
        XCTAssertEqual(BackoffPolicy.delay(attempt: 10), 60)
    }

    func testLargeAttemptDoesNotOverflow() {
        XCTAssertEqual(BackoffPolicy.delay(attempt: 1000), 60)
    }
}
