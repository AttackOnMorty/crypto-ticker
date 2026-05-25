import XCTest
@testable import CryptoTickerCore

/// The pure connect/disconnect/reconnect decisions, isolated from the live sockets.
final class WebSocketPlanTests: XCTestCase {

    // MARK: diff (drives connectWebSockets)

    func testDisconnectsSymbolsNoLongerSelected() {
        let result = WebSocketPlan.symbolsToDisconnect(selected: ["btcusdt"], active: ["btcusdt", "ethusdt", "xrpusdt"])
        XCTAssertEqual(result, ["ethusdt", "xrpusdt"])
    }

    func testConnectsSelectedSymbolsThatHaveNoActiveTask() {
        let result = WebSocketPlan.symbolsToConnect(selected: ["btcusdt", "ethusdt", "xrpusdt"], active: ["btcusdt"])
        XCTAssertEqual(result, ["ethusdt", "xrpusdt"])
    }

    func testConnectPreservesSelectionOrder() {
        let result = WebSocketPlan.symbolsToConnect(selected: ["ethusdt", "btcusdt"], active: [])
        XCTAssertEqual(result, ["ethusdt", "btcusdt"])
    }

    // MARK: reconnect guard (F2/F3/F4)

    func testReconnectsWhenStillSelectedAndNoActiveTask() {
        // F3: a failed task has been removed from the active set, so reconnect proceeds.
        XCTAssertTrue(WebSocketPlan.shouldReconnect("btcusdt", selected: ["btcusdt"], active: []))
    }

    func testDoesNotReconnectWhenDeselected() {
        // F4: a cancel caused by the user toggling off must not trigger a reconnect.
        XCTAssertFalse(WebSocketPlan.shouldReconnect("btcusdt", selected: [], active: []))
    }

    func testDoesNotReconnectWhenATaskAlreadyExists() {
        // F2: don't overwrite a socket established during the reconnect delay.
        XCTAssertFalse(WebSocketPlan.shouldReconnect("btcusdt", selected: ["btcusdt"], active: ["btcusdt"]))
    }
}
