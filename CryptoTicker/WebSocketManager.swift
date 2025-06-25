import Foundation
import os.log

enum WebSocketError: Error {
    case invalidURL
    case connectionFailed
    case dataParsingFailed
    case networkError(Error)
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
        CryptoCurrency(code: "SOL", name: "Solana", symbol: "solusdt", icon: "S"),
        CryptoCurrency(code: "BNB", name: "BNB", symbol: "bnbusdt", icon: "B"),
        CryptoCurrency(code: "DOGE", name: "Dogecoin", symbol: "dogeusdt", icon: "Ɖ"),
        CryptoCurrency(code: "ADA", name: "Cardano", symbol: "adausdt", icon: "₳"),
        CryptoCurrency(code: "TRX", name: "TRON", symbol: "trxusdt", icon: "T"),
        CryptoCurrency(code: "LINK", name: "Chainlink", symbol: "linkusdt", icon: "L"),
        CryptoCurrency(code: "AVAX", name: "Avalanche", symbol: "avaxusdt", icon: "A")
    ]
}

class WebSocketManager: ObservableObject {
    @Published var prices: [String: String] = [:]
    @Published var selectedSymbols: [String] = []
    @Published var priceChanges: [String: String] = [:]
    @Published var connectionStates: [String: ConnectionState] = [:]
    @Published var lastPriceUpdateTime: Date = Date()
    
    private var webSocketTasks: [String: URLSessionWebSocketTask] = [:]
    private let urlSession = URLSession(configuration: .default)
    private let logger = Logger(subsystem: AppConfiguration.Logging.subsystem, category: "WebSocketManager")
    private var priceRefreshTimer: Timer?
    
    let availableCurrencies = CryptoCurrency.availableCurrencies
    
    init() {
        loadSelectedCryptos()
        Task {
            await fetchAllCryptoPrices()
            connectWebSockets()
        }
        startPeriodicPriceRefresh()
    }
    
    // MARK: - Configuration Management
    
    private func loadSelectedCryptos() {
        selectedSymbols = UserDefaults.standard.array(forKey: AppConfiguration.UserDefaultsKeys.selectedCryptos) as? [String] ?? AppConfiguration.Defaults.selectedCryptos
        logger.info("Loaded selected cryptos: \(self.selectedSymbols)")
    }
    
    private func saveSelectedCryptos() {
        UserDefaults.standard.set(selectedSymbols, forKey: AppConfiguration.UserDefaultsKeys.selectedCryptos)
        logger.info("Saved selected cryptos: \(self.selectedSymbols)")
    }
    
    // MARK: - Price Fetching
    
    func fetchAllCryptoPrices() async {
        logger.info("Fetching prices for all \(self.availableCurrencies.count) cryptocurrencies")
        
        await withTaskGroup(of: Void.self) { group in
            for currency in self.availableCurrencies {
                group.addTask {
                    await self.fetchPrice(for: currency.symbol)
                }
            }
        }
        
        // Update the last refresh time
        await MainActor.run {
            self.lastPriceUpdateTime = Date()
            UserDefaults.standard.set(Date(), forKey: AppConfiguration.UserDefaultsKeys.lastUpdateTime)
        }
        
        logger.info("Completed fetching all cryptocurrency prices")
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
            
            await MainActor.run {
                self.prices[symbol] = self.formatPrice(priceStr)
                self.priceChanges[symbol] = self.formatPercent(changeStr) + "%"
                NotificationCenter.default.post(name: NSNotification.Name("PriceUpdated"), object: nil)
            }
            
            logger.info("Updated price for \(symbol): \(priceStr)")
            
        } catch {
            logger.error("Failed to fetch price for \(symbol): \(error.localizedDescription)")
        }
    }
    
    // MARK: - WebSocket Management
    
    func connectWebSockets() {
        // Disconnect any websockets that are no longer selected
        let symbolsToDisconnect = Set(webSocketTasks.keys).subtracting(Set(selectedSymbols))
        for symbol in symbolsToDisconnect {
            disconnectWebSocket(for: symbol)
        }
        
        // Connect websockets for newly selected symbols
        for symbol in selectedSymbols {
            if webSocketTasks[symbol] == nil {
                connectWebSocket(for: symbol)
            }
        }
    }
    
    private func connectWebSocket(for symbol: String) {
        guard let url = URL(string: "\(AppConfiguration.API.binanceWebSocketURL)/\(symbol)@trade") else {
            logger.error("Invalid WebSocket URL for symbol: \(symbol)")
            updateConnectionState(for: symbol, state: .error(.invalidURL))
            return
        }
        
        logger.info("Connecting WebSocket for \(symbol)")
        updateConnectionState(for: symbol, state: .connecting)
        
        let task = urlSession.webSocketTask(with: url)
        webSocketTasks[symbol] = task
        
        task.resume()
        receiveMessage(for: symbol)
        
        // Only mark as connected after we start receiving messages
        // The connection state will be updated in receiveMessage on first success
    }
    
    private func receiveMessage(for symbol: String) {
        guard let task = webSocketTasks[symbol] else { 
            logger.debug("No WebSocket task found for \(symbol), stopping message reception")
            return 
        }
        
        task.receive { [weak self] result in
            guard let self = self else { return }
            
            // Check if this symbol is still selected before processing
            guard self.selectedSymbols.contains(symbol) else {
                self.logger.debug("Symbol \(symbol) no longer selected, stopping message reception")
                return
            }
            
            switch result {
            case .success(let message):
                // Mark as connected on first successful message
                if case .connecting = self.connectionStates[symbol] {
                    self.updateConnectionState(for: symbol, state: .connected)
                }
                
                if case .string(let text) = message {
                    self.handleIncomingData(text, for: symbol)
                }
                self.receiveMessage(for: symbol) // Continue listening
                
            case .failure(let error):
                self.logger.error("WebSocket error for \(symbol): \(error.localizedDescription)")
                self.updateConnectionState(for: symbol, state: .error(.networkError(error)))
                
                // Only attempt reconnection if symbol is still selected
                if self.selectedSymbols.contains(symbol) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + AppConfiguration.WebSocket.reconnectDelay) {
                        if self.selectedSymbols.contains(symbol) {
                            self.connectWebSocket(for: symbol)
                        }
                    }
                }
            }
        }
    }
    
    private func handleIncomingData(_ text: String, for symbol: String) {
        // Double-check that this symbol is still selected
        guard selectedSymbols.contains(symbol) else {
            logger.debug("Ignoring price update for unselected symbol: \(symbol)")
            return
        }
        
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let priceStr = json["p"] as? String else {
            logger.error("Failed to parse WebSocket data for \(symbol)")
            return
        }
        
        DispatchQueue.main.async {
            // Final check before updating price
            guard self.selectedSymbols.contains(symbol) else {
                self.logger.debug("Symbol \(symbol) deselected during price update, skipping")
                return
            }
            
            self.prices[symbol] = self.formatPrice(priceStr)
            NotificationCenter.default.post(name: NSNotification.Name("PriceUpdated"), object: nil)
        }
        
        logger.debug("Received WebSocket price update for \(symbol): \(priceStr)")
    }
    
    private func updateConnectionState(for symbol: String, state: ConnectionState) {
        DispatchQueue.main.async {
            self.connectionStates[symbol] = state
            // Notify UI to update connection indicators immediately
            NotificationCenter.default.post(
                name: NSNotification.Name("ConnectionStateChanged"), 
                object: nil, 
                userInfo: ["symbol": symbol, "state": state]
            )
        }
    }
    
    func disconnectWebSockets() {
        logger.info("Disconnecting all WebSockets")
        
        let allSymbols = Array(webSocketTasks.keys)
        for symbol in allSymbols {
            disconnectWebSocket(for: symbol)
        }
    }
    
    private func disconnectWebSocket(for symbol: String) {
        guard let task = webSocketTasks[symbol] else { return }
        
        logger.info("Disconnecting WebSocket for \(symbol)")
        task.cancel(with: .goingAway, reason: nil)
        webSocketTasks.removeValue(forKey: symbol)
        updateConnectionState(for: symbol, state: .disconnected)
    }
    
    // MARK: - Selection Management
    
    func toggleCryptoSelection(_ symbol: String) {
        if let index = selectedSymbols.firstIndex(of: symbol) {
            selectedSymbols.remove(at: index)
            logger.info("Removed \(symbol) from selection")
        } else {
            selectedSymbols.append(symbol)
            logger.info("Added \(symbol) to selection")
        }
        
        saveSelectedCryptos()
        connectWebSockets()
    }
    
    func selectCrypto(_ symbol: String) {
        guard !selectedSymbols.contains(symbol) else { return }
        selectedSymbols.append(symbol)
        saveSelectedCryptos()
        connectWebSocket(for: symbol)
    }
    
    func deselectCrypto(_ symbol: String) {
        guard let index = selectedSymbols.firstIndex(of: symbol) else { return }
        selectedSymbols.remove(at: index)
        disconnectWebSocket(for: symbol)
        saveSelectedCryptos()
        logger.info("Deselected crypto: \(symbol)")
    }
    
    // MARK: - Formatting Utilities
    
    private func formatPrice(_ price: String) -> String {
        guard let priceDouble = Double(price) else { return price }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        
        // Dynamic precision based on price range
        formatter.maximumFractionDigits = {
            switch priceDouble {
            case 100...: return 0
            case 1..<100: return 1
            case 0.1..<1: return 3
            default: return 8
            }
        }()
        
        return formatter.string(from: NSNumber(value: priceDouble)) ?? price
    }
    
    private func formatPercent(_ percent: String) -> String {
        guard let percentDouble = Double(percent) else { return percent }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        
        return formatter.string(from: NSNumber(value: percentDouble)) ?? percent
    }
    
    // MARK: - Utility Methods
    
    func getCurrency(for symbol: String) -> CryptoCurrency? {
        return availableCurrencies.first { $0.symbol == symbol }
    }
    
    func isConnected(for symbol: String) -> Bool {
        if case .connected = connectionStates[symbol] {
            return true
        }
        return false
    }
    
    private func shouldMaintainConnection(for symbol: String) -> Bool {
        return selectedSymbols.contains(symbol)
    }
    
    func getTimeSinceLastUpdate() -> String {
        let timeInterval = Date().timeIntervalSince(lastPriceUpdateTime)
        let minutes = Int(timeInterval / 60)
        
        if minutes < 1 {
            return "Just now"
        } else if minutes == 1 {
            return "1 minute ago"
        } else if minutes < 60 {
            return "\(minutes) minutes ago"
        } else {
            let hours = minutes / 60
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
    }
    
    // MARK: - Periodic Price Refresh
    
    private func startPeriodicPriceRefresh() {
        logger.info("Starting periodic price refresh every \(AppConfiguration.Defaults.allPricesRefreshInterval/60) minutes")
        
        priceRefreshTimer = Timer.scheduledTimer(withTimeInterval: AppConfiguration.Defaults.allPricesRefreshInterval, repeats: true) { [weak self] _ in
            self?.performPeriodicRefresh()
        }
    }
    
    private func performPeriodicRefresh() {
        logger.info("Performing periodic price refresh for all cryptocurrencies")
        Task {
            await fetchAllCryptoPrices()
        }
    }
    
    private func stopPeriodicPriceRefresh() {
        priceRefreshTimer?.invalidate()
        priceRefreshTimer = nil
        logger.info("Stopped periodic price refresh")
    }
    
    deinit {
        stopPeriodicPriceRefresh()
        disconnectWebSockets()
    }
}
