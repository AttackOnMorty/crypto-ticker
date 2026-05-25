import XCTest
@testable import CryptoTickerCore

/// Confirms the harness compiles the app sources and can reach their symbols.
final class SmokeTests: XCTestCase {
    func testAvailableCurrenciesExposed() {
        XCTAssertFalse(CryptoCurrency.availableCurrencies.isEmpty)
    }
}
