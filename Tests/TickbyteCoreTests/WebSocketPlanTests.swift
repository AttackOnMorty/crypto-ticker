import XCTest
@testable import TickbyteCore

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

    // MARK: residual-state cleanup (F3) — forget state for a deselected, socket-less symbol

    func testForgetsTrackedSymbolNoLongerSelectedWithNoActiveSocket() {
        // Failed-then-deselected during backoff: the task is already gone from `active`,
        // but stale .error state and the reconnect-attempt counter linger — clear them.
        let result = WebSocketPlan.symbolsToForget(selected: ["btcusdt"], tracked: ["btcusdt", "ethusdt"], active: [])
        XCTAssertEqual(result, ["ethusdt"])
    }

    func testDoesNotForgetActiveSymbol() {
        // An active socket that was deselected is handled by the disconnect path, not here.
        let result = WebSocketPlan.symbolsToForget(selected: [], tracked: ["btcusdt"], active: ["btcusdt"])
        XCTAssertEqual(result, [])
    }

    func testDoesNotForgetSelectedSymbol() {
        let result = WebSocketPlan.symbolsToForget(selected: ["btcusdt"], tracked: ["btcusdt"], active: [])
        XCTAssertEqual(result, [])
    }

    // MARK: connected promotion (F2) — a liveness signal promotes only a connecting socket

    func testPromotesToConnectedWhenConnecting() {
        XCTAssertTrue(WebSocketPlan.shouldPromoteToConnected(from: .connecting))
    }

    func testDoesNotPromoteWhenAlreadyConnected() {
        XCTAssertFalse(WebSocketPlan.shouldPromoteToConnected(from: .connected))
    }

    func testDoesNotPromoteFromDisconnectedOrError() {
        // A stale liveness signal must not resurrect a torn-down socket.
        XCTAssertFalse(WebSocketPlan.shouldPromoteToConnected(from: .disconnected))
        XCTAssertFalse(WebSocketPlan.shouldPromoteToConnected(from: .error(.invalidURL)))
    }

    func testDoesNotPromoteFromNoState() {
        XCTAssertFalse(WebSocketPlan.shouldPromoteToConnected(from: nil))
    }

    // MARK: socket identity (run3 F1/F2) — a stale callback from a replaced socket is ignored

    func testIsCurrentSocketTrueForSameInstance() {
        let task = NSObject()
        XCTAssertTrue(WebSocketPlan.isCurrentSocket(task, current: task))
    }

    func testIsCurrentSocketFalseForDifferentInstance() {
        // Socket A's late callback must not act on the healthy replacement socket B.
        let a = NSObject()
        let b = NSObject()
        XCTAssertFalse(WebSocketPlan.isCurrentSocket(a, current: b))
    }

    func testIsCurrentSocketFalseWhenNoCurrentSocket() {
        XCTAssertFalse(WebSocketPlan.isCurrentSocket(NSObject(), current: nil))
    }
}
