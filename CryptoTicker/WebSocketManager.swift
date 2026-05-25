import Foundation
import os.log

extension Notification.Name {
    static let priceUpdated = Notification.Name("PriceUpdated")
    static let connectionStateChanged = Notification.Name("ConnectionStateChanged")
}

enum WebSocketError: Error {
    case invalidURL
    case networkError(Error)
}

/// A Binance `@trade` message. Only the price (`p`) is decoded — decoding into a typed
/// struct skips boxing every field into a dictionary on the per-trade hot path (F8).
struct TradeMessage: Decodable {
    let price: String

    private enum CodingKeys: String, CodingKey { case price = "p" }

    private static let decoder = JSONDecoder()

    static func price(fromJSON text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let message = try? decoder.decode(TradeMessage.self, from: data) else {
            return nil
        }
        return message.price
    }
}

enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case error(WebSocketError)
}

@MainActor
class WebSocketManager {
    // All mutable state below is confined to the main actor. The only off-actor work is
    // the network I/O itself, which hops back to the main actor before touching any of it.

    /// Formatted display strings (already through `PriceFormatter.price`).
    var prices: [String: String] = [:]
    var selectedSymbols: [String] = []
    /// RAW 24h change strings (e.g. "2.50"), formatted at display time. Stored raw on
    /// purpose so the colour decision (`PriceFormatter.percentValue`) parses the number
    /// directly instead of round-tripping a formatted string — do not pre-format here.
    var priceChanges: [String: String] = [:]
    var connectionStates: [String: ConnectionState] = [:]

    /// Set by the menu delegate. Live trade updates are only published while the menu is
    /// visible — when it's closed the 1 Hz status-bar timer is the only consumer and reads
    /// state directly, so a per-trade notification would be wasted work (F7).
    var isMenuVisible = false

    private var webSocketTasks: [String: URLSessionWebSocketTask] = [:]
    private var reconnectAttempts: [String: Int] = [:]
    private var pingTimer: Timer?
    private let urlSession = URLSession(configuration: .default)
    private let logger = Logger(subsystem: AppConfiguration.Logging.subsystem, category: "WebSocketManager")

    let availableCurrencies = CryptoCurrency.availableCurrencies

    init() {
        loadSelectedCryptos()
        // F10: only the selected symbols are shown at launch; the others are fetched
        // lazily when the menu first opens.
        Task { @MainActor in
            await fetchPrices(for: selectedSymbols)
            connectWebSockets()
        }
        startPingTimer()
    }

    private func loadSelectedCryptos() {
        let stored = UserDefaults.standard.array(forKey: AppConfiguration.UserDefaultsKeys.selectedCryptos) as? [String] ?? AppConfiguration.Defaults.selectedCryptos
        selectedSymbols = CryptoCurrency.validSymbols(from: stored)
    }

    private func saveSelectedCryptos() {
        UserDefaults.standard.set(selectedSymbols, forKey: AppConfiguration.UserDefaultsKeys.selectedCryptos)
    }

    func fetchAllCryptoPrices() async {
        await fetchPrices(for: availableCurrencies.map(\.symbol))
    }

    func fetchPrices(for symbols: [String]) async {
        logger.info("Fetching prices for \(symbols.count) symbols")
        await withTaskGroup(of: Void.self) { group in
            for symbol in symbols {
                group.addTask { await self.fetchPrice(for: symbol) }
            }
        }
    }

    private func fetchPrice(for symbol: String) async {
        guard let url = URL(string: "\(AppConfiguration.API.binanceBaseURL)/ticker/24hr?symbol=\(symbol.uppercased())") else {
            logger.error("Invalid URL for symbol: \(symbol)")
            return
        }

        do {
            let (data, _) = try await urlSession.data(from: url)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let priceStr = json["lastPrice"] as? String,
                  let changeStr = json["priceChangePercent"] as? String else {
                logger.error("Failed to parse price data for \(symbol)")
                return
            }

            // Already back on the main actor after the await. No notification here (F9):
            // the status bar reads state via its timer, and the menu refreshes explicitly
            // after its on-open fetch batch — posting per symbol caused redundant refreshes.
            prices[symbol] = PriceFormatter.price(priceStr)
            priceChanges[symbol] = changeStr
        } catch {
            logger.error("Failed to fetch price for \(symbol): \(error.localizedDescription)")
        }
    }

    func connectWebSockets() {
        let active = Set(webSocketTasks.keys)
        for symbol in WebSocketPlan.symbolsToDisconnect(selected: selectedSymbols, active: active) {
            disconnectWebSocket(for: symbol)
        }
        for symbol in WebSocketPlan.symbolsToConnect(selected: selectedSymbols, active: active) {
            connectWebSocket(for: symbol)
        }
    }

    private func connectWebSocket(for symbol: String) {
        guard let url = URL(string: "\(AppConfiguration.API.binanceWebSocketURL)/\(symbol)@trade") else {
            logger.error("Invalid WebSocket URL for symbol: \(symbol)")
            updateConnectionState(for: symbol, state: .error(.invalidURL))
            return
        }

        updateConnectionState(for: symbol, state: .connecting)

        let task = urlSession.webSocketTask(with: url)
        webSocketTasks[symbol] = task

        task.resume()
        receiveMessage(for: symbol)
    }

    private func receiveMessage(for symbol: String) {
        guard let task = webSocketTasks[symbol] else { return }

        // The completion runs on URLSession's background queue; hop to the main actor
        // before touching any shared state (F1).
        task.receive { [weak self] result in
            Task { @MainActor in
                self?.handleReceive(result, for: symbol, task: task)
            }
        }
    }

    private func handleReceive(_ result: Result<URLSessionWebSocketTask.Message, Error>, for symbol: String, task: URLSessionWebSocketTask) {
        // Ignore a callback for a deselected symbol (the cancel path), or one from a socket
        // already replaced by a healthy reconnect — identity, not mere presence (run3 F1/F2).
        guard selectedSymbols.contains(symbol),
              WebSocketPlan.isCurrentSocket(task, current: webSocketTasks[symbol]) else { return }

        switch result {
        case .success(let message):
            if case .connecting = connectionStates[symbol] {
                updateConnectionState(for: symbol, state: .connected)
                reconnectAttempts[symbol] = 0 // a successful connect resets the backoff
            }
            if case .string(let text) = message {
                handleIncomingData(text, for: symbol)
            }
            receiveMessage(for: symbol) // Continue listening

        case .failure(let error):
            handleConnectionFailure(error, for: symbol, task: task)
        }
    }

    // F1: a half-open connection delivers neither data nor a `.failure`, so the receive
    // loop alone can't detect it. Periodically ping every active socket; a ping error means
    // the connection is dead — tear it down and reconnect (with backoff).
    private func startPingTimer() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: AppConfiguration.WebSocket.pingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pingActiveSockets() }
        }
    }

    private func pingActiveSockets() {
        for (symbol, task) in webSocketTasks {
            task.sendPing { [weak self] error in
                guard let error else { return } // healthy: pong handled by the framework
                Task { @MainActor in self?.handleConnectionFailure(error, for: symbol, task: task) }
            }
        }
    }

    /// Single failure path for both receive errors and failed keepalive pings. Acts only if
    /// `task` is still the current socket for `symbol`, so a stale callback from a socket
    /// already replaced by a reconnect can't tear down the healthy one (run3 F1/F2/F4).
    private func handleConnectionFailure(_ error: Error, for symbol: String, task: URLSessionWebSocketTask) {
        guard WebSocketPlan.isCurrentSocket(task, current: webSocketTasks[symbol]) else { return }
        logger.error("WebSocket failure for \(symbol): \(error.localizedDescription)")
        task.cancel(with: .goingAway, reason: nil)
        webSocketTasks.removeValue(forKey: symbol)
        updateConnectionState(for: symbol, state: .error(.networkError(error)))
        scheduleReconnect(for: symbol)
    }

    private func scheduleReconnect(for symbol: String) {
        let attempt = reconnectAttempts[symbol, default: 0]
        reconnectAttempts[symbol] = attempt + 1
        let delay = BackoffPolicy.delay(attempt: attempt) // F2: exponential backoff, capped
        Task { @MainActor [weak self] in // F5: don't pin the manager past the delay
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            // F2/F4: reconnect only if still selected and nothing reconnected meanwhile.
            guard WebSocketPlan.shouldReconnect(symbol, selected: self.selectedSymbols, active: Set(self.webSocketTasks.keys)) else { return }
            self.connectWebSocket(for: symbol)
        }
    }

    private func handleIncomingData(_ text: String, for symbol: String) {
        guard selectedSymbols.contains(symbol) else { return }

        guard let priceStr = TradeMessage.price(fromJSON: text) else {
            logger.error("Failed to parse WebSocket data for \(symbol)")
            return
        }

        prices[symbol] = PriceFormatter.price(priceStr)
        if isMenuVisible { // F7: only refresh the menu when it's actually on screen
            NotificationCenter.default.post(name: .priceUpdated, object: nil)
        }
    }

    private func updateConnectionState(for symbol: String, state: ConnectionState) {
        connectionStates[symbol] = state
        NotificationCenter.default.post(name: .connectionStateChanged, object: nil)
    }

    func disconnectWebSockets() {
        logger.info("Disconnecting all WebSockets")
        pingTimer?.invalidate()
        webSocketTasks.keys.forEach { disconnectWebSocket(for: $0) }
    }

    private func disconnectWebSocket(for symbol: String) {
        guard let task = webSocketTasks[symbol] else { return }

        task.cancel(with: .goingAway, reason: nil)
        webSocketTasks.removeValue(forKey: symbol)
        reconnectAttempts.removeValue(forKey: symbol)
        updateConnectionState(for: symbol, state: .disconnected)
    }

    func toggleCryptoSelection(_ symbol: String) {
        if let index = selectedSymbols.firstIndex(of: symbol) {
            selectedSymbols.remove(at: index)
        } else {
            selectedSymbols.append(symbol)
        }
        saveSelectedCryptos()
        connectWebSockets()
    }

    func getCurrency(for symbol: String) -> CryptoCurrency? {
        return availableCurrencies.first { $0.symbol == symbol }
    }

    func isConnected(for symbol: String) -> Bool {
        if case .connected = connectionStates[symbol] { return true }
        return false
    }
}
