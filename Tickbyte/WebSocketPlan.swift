//
//  WebSocketPlan.swift
//  Tickbyte
//

import Foundation

/// Pure decisions about which sockets to open, close, or reconnect. Kept separate from
/// the side-effecting socket code so the logic can be tested without live connections.
enum WebSocketPlan {
    /// Active sockets whose symbols are no longer selected.
    static func symbolsToDisconnect(selected: [String], active: Set<String>) -> Set<String> {
        active.subtracting(selected)
    }

    /// Selected symbols that have no active socket yet (selection order preserved).
    static func symbolsToConnect(selected: [String], active: Set<String>) -> [String] {
        selected.filter { !active.contains($0) }
    }

    /// Symbols whose residual state (connection state, reconnect-attempt counter) should be
    /// discarded: tracked but no longer selected and with no active socket. Active-but-
    /// deselected symbols are excluded — the disconnect path already resets their state.
    static func symbolsToForget(selected: [String], tracked: Set<String>, active: Set<String>) -> Set<String> {
        tracked.subtracting(selected).subtracting(active)
    }

    /// Whether a failed socket should be reconnected: only if the symbol is still selected
    /// and no socket currently exists for it (so a reconnect can't duplicate a live socket).
    static func shouldReconnect(_ symbol: String, selected: [String], active: Set<String>) -> Bool {
        selected.contains(symbol) && !active.contains(symbol)
    }

    /// Whether a socket callback should be acted on: only if the task that fired it is still
    /// the current socket for the symbol. A stale callback from a socket already replaced by
    /// a healthy reconnect is ignored — identity, not mere presence.
    static func isCurrentSocket(_ reported: AnyObject, current: AnyObject?) -> Bool {
        reported === current
    }

    /// Whether a liveness signal (a received message or a successful keepalive ping) should
    /// promote the connection to `.connected`. Only a `.connecting` socket promotes; a stale
    /// signal must not resurrect a `.disconnected`/`.error` socket being torn down.
    static func shouldPromoteToConnected(from state: ConnectionState?) -> Bool {
        if case .connecting = state { return true }
        return false
    }
}

/// Exponential reconnect backoff with a ceiling, so a sustained outage retries on a
/// widening interval (base → cap) instead of a fixed-rate hammer.
enum BackoffPolicy {
    static func delay(attempt: Int) -> TimeInterval {
        let exponent = Double(min(max(attempt, 0), 32)) // clamp to avoid overflow
        let delay = AppConfiguration.WebSocket.reconnectDelay * pow(2, exponent)
        return min(delay, AppConfiguration.WebSocket.maxReconnectDelay)
    }
}
