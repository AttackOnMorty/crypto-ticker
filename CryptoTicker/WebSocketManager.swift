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

struct CryptoCurrency {
    let code: String
    let name: String
    let symbol: String
    let icon: String
    
    static let availableCurrencies = [
        CryptoCurrency(code: "BTC", name: "Bitcoin", symbol: "btcusdt", icon: "₿"),
        CryptoCurrency(code: "ETH", name: "Ethereum", symbol: "ethusdt", icon: "Ξ"),
        CryptoCurrency(code: "XRP", name: "XRP", symbol: "xrpusdt", icon: "✕"),
        CryptoCurrency(code: "BNB", name: "BNB", symbol: "bnbusdt", icon: "B"),
        CryptoCurrency(code: "SOL", name: "Solana", symbol: "solusdt", icon: "S"),
        CryptoCurrency(code: "DOGE", name: "Dogecoin", symbol: "dogeusdt", icon: "Ɖ"),
        CryptoCurrency(code: "TRX", name: "TRON", symbol: "trxusdt", icon: "T")
    ]

    /// Keeps only symbols that exist in `availableCurrencies`, preserving order. Used to
    /// sanitize values loaded from UserDefaults so a tampered plist cannot inject an
    /// arbitrary segment into the request URLs.
    static func validSymbols(from raw: [String]) -> [String] {
        let known = Set(availableCurrencies.map(\.symbol))
        return raw.filter { known.contains($0) }
    }
}

/// Single source of truth for turning raw feed strings into display text.
///
/// Formatters are created once and reused (creating a `NumberFormatter` per call is
/// expensive on the per-trade hot path), and they are immutable so they are safe to read
/// from any thread. Unparseable input returns `placeholder` rather than echoing the raw,
/// untrusted feed string back into the UI.
enum PriceFormatter {
    static let placeholder = "—"

    private static func decimalFormatter(fractionDigits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter
    }

    private static let wholeFormatter = decimalFormatter(fractionDigits: 0)
    private static let twoDecimalFormatter = decimalFormatter(fractionDigits: 2)
    private static let fourDecimalFormatter = decimalFormatter(fractionDigits: 4)

    /// Formats a price with magnitude-dependent precision: >= 1000 → whole dollars,
    /// >= 1 → 2 decimals, < 1 → 4 decimals.
    static func price(_ raw: String) -> String {
        guard let value = Double(raw) else { return placeholder }
        let formatter: NumberFormatter
        switch value {
        case 1000...: formatter = wholeFormatter
        case 1..<1000: formatter = twoDecimalFormatter
        default: formatter = fourDecimalFormatter
        }
        return formatter.string(from: NSNumber(value: value)) ?? placeholder
    }

    /// Formats a 24h change percentage as a signed, 2-decimal value with a trailing `%`.
    static func percent(_ raw: String) -> String {
        guard let value = Double(raw) else { return placeholder }
        return String(format: "%+.2f%%", value)
    }

    /// The numeric value of a raw percentage string, for choosing a colour. Parses the
    /// raw number directly — never a previously formatted string — so there is no
    /// format/parse round-trip.
    static func percentValue(_ raw: String) -> Double? {
        Double(raw)
    }
}

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

    /// Whether a failed socket should be reconnected: only if the symbol is still selected
    /// and no socket currently exists for it (so a reconnect can't duplicate a live socket).
    static func shouldReconnect(_ symbol: String, selected: [String], active: Set<String>) -> Bool {
        selected.contains(symbol) && !active.contains(symbol)
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

/// Builds the status-bar title from already-resolved per-symbol items. Pure, so the
/// formatting rules (separator, indicators, empty-state text) are testable without AppKit.
enum StatusBarText {
    struct Item {
        let icon: String
        let price: String
        let indicator: String
    }

    static func indicator(for state: ConnectionState?) -> String {
        switch state {
        case .connected: return ""
        case .connecting: return "⏳"
        case .disconnected, .error, .none: return "⚠️"
        }
    }

    static func make(items: [Item]) -> String {
        guard !items.isEmpty else { return "CRYPTO TICKER" }
        return items.map { "\($0.icon) \($0.price) \($0.indicator)" }.joined(separator: "| ")
    }
}

@MainActor
class WebSocketManager {
    // All mutable state below is confined to the main actor. The only off-actor work is
    // the network I/O itself, which hops back to the main actor before touching any of it.
    var prices: [String: String] = [:]
    var selectedSymbols: [String] = []
    var priceChanges: [String: String] = [:]
    var connectionStates: [String: ConnectionState] = [:]

    private var webSocketTasks: [String: URLSessionWebSocketTask] = [:]
    private var reconnectAttempts: [String: Int] = [:]
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
            let (data, _) = try await URLSession.shared.data(from: url)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let priceStr = json["lastPrice"] as? String,
                  let changeStr = json["priceChangePercent"] as? String else {
                logger.error("Failed to parse price data for \(symbol)")
                return
            }

            // Already back on the main actor after the await.
            prices[symbol] = PriceFormatter.price(priceStr)
            priceChanges[symbol] = changeStr
            NotificationCenter.default.post(name: .priceUpdated, object: nil)
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
                self?.handleReceive(result, for: symbol)
            }
        }
    }

    private func handleReceive(_ result: Result<URLSessionWebSocketTask.Message, Error>, for symbol: String) {
        // If the symbol was deselected (the cancel path), ignore the callback entirely —
        // don't clobber the disconnected state or schedule a reconnect (F4).
        guard selectedSymbols.contains(symbol) else { return }

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
            logger.error("WebSocket error for \(symbol): \(error.localizedDescription)")
            // F3: drop the failed task so the diff/reconnect logic sees no active socket.
            webSocketTasks.removeValue(forKey: symbol)
            updateConnectionState(for: symbol, state: .error(.networkError(error)))
            scheduleReconnect(for: symbol)
        }
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
        NotificationCenter.default.post(name: .priceUpdated, object: nil)
    }

    private func updateConnectionState(for symbol: String, state: ConnectionState) {
        connectionStates[symbol] = state
        NotificationCenter.default.post(name: .connectionStateChanged, object: nil)
    }
    
    func disconnectWebSockets() {
        logger.info("Disconnecting all WebSockets")
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
