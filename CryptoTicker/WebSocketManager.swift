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
        CryptoCurrency(code: "BNB", name: "BNB", symbol: "bnbusdt", icon: "B"),
        CryptoCurrency(code: "SOL", name: "Solana", symbol: "solusdt", icon: "S"),
        CryptoCurrency(code: "DOGE", name: "Dogecoin", symbol: "dogeusdt", icon: "Ɖ"),
        CryptoCurrency(code: "TRX", name: "TRON", symbol: "trxusdt", icon: "T")
    ]
}

class WebSocketManager: ObservableObject {
    @Published var prices: [String: String] = [:]
    @Published var selectedSymbols: [String] = []
    @Published var priceChanges: [String: String] = [:]
    @Published var connectionStates: [String: ConnectionState] = [:]
    
    private var webSocketTasks: [String: URLSessionWebSocketTask] = [:]
    private let urlSession = URLSession(configuration: .default)
    private let logger = Logger(subsystem: AppConfiguration.Logging.subsystem, category: "WebSocketManager")
    
    let availableCurrencies = CryptoCurrency.availableCurrencies
    
    init() {
        loadSelectedCryptos()
        Task {
            await fetchAllCryptoPrices()
            connectWebSockets()
        }
    }

    private func loadSelectedCryptos() {
        selectedSymbols = UserDefaults.standard.array(forKey: AppConfiguration.UserDefaultsKeys.selectedCryptos) as? [String] ?? AppConfiguration.Defaults.selectedCryptos
    }
    
    private func saveSelectedCryptos() {
        UserDefaults.standard.set(selectedSymbols, forKey: AppConfiguration.UserDefaultsKeys.selectedCryptos)
    }

    func fetchAllCryptoPrices() async {
        logger.info("Fetching prices for all \(self.availableCurrencies.count) cryptocurrencies")
        
        await withTaskGroup(of: Void.self) { group in
            for currency in self.availableCurrencies {
                group.addTask {
                    await self.fetchPrice(for: currency.symbol)
                }
            }
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
            
        } catch {
            logger.error("Failed to fetch price for \(symbol): \(error.localizedDescription)")
        }
    }

    func connectWebSockets() {
        let symbolsToDisconnect = Set(webSocketTasks.keys).subtracting(Set(selectedSymbols))
        for symbol in symbolsToDisconnect {
            disconnectWebSocket(for: symbol)
        }

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

        updateConnectionState(for: symbol, state: .connecting)
        
        let task = urlSession.webSocketTask(with: url)
        webSocketTasks[symbol] = task
        
        task.resume()
        receiveMessage(for: symbol)
    }
    
    private func receiveMessage(for symbol: String) {
        guard let task = webSocketTasks[symbol] else { return }
        
        task.receive { [weak self] result in
            guard let self = self else { return }

            guard self.selectedSymbols.contains(symbol) else { return }
            
            switch result {
            case .success(let message):
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
        guard selectedSymbols.contains(symbol) else { return }
        
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let priceStr = json["p"] as? String else {
            logger.error("Failed to parse WebSocket data for \(symbol)")
            return
        }
        
        DispatchQueue.main.async {
            guard self.selectedSymbols.contains(symbol) else { return }

            self.prices[symbol] = self.formatPrice(priceStr)
            NotificationCenter.default.post(name: NSNotification.Name("PriceUpdated"), object: nil)
        }
    }
    
    private func updateConnectionState(for symbol: String, state: ConnectionState) {
        DispatchQueue.main.async {
            self.connectionStates[symbol] = state
            NotificationCenter.default.post(
                name: NSNotification.Name("ConnectionStateChanged"),
                object: nil,
                userInfo: ["symbol": symbol, "state": state]
            )
        }
    }
    
    func disconnectWebSockets() {
        logger.info("Disconnecting all WebSockets")
        webSocketTasks.keys.forEach { disconnectWebSocket(for: $0) }
    }
    
    private func disconnectWebSocket(for symbol: String) {
        guard let task = webSocketTasks[symbol] else { return }

        task.cancel(with: .goingAway, reason: nil)
        webSocketTasks.removeValue(forKey: symbol)
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
    

    private func formatPrice(_ price: String) -> String {
        guard let priceDouble = Double(price) else { return price }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true

        formatter.maximumFractionDigits = {
            switch priceDouble {
            case 1000...: return 0  // >= 1000, no decimal digits
            case 1..<1000: return 2  // >= 1, 2 decimal digits
            default: return 4         // < 1, 4 decimal digits
            }
        }()

        return formatter.string(from: NSNumber(value: priceDouble)) ?? price
    }
    
    private func formatPercent(_ percent: String) -> String {
        guard let percentDouble = Double(percent) else { return percent }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"

        return formatter.string(from: NSNumber(value: percentDouble)) ?? percent
    }

    func getCurrency(for symbol: String) -> CryptoCurrency? {
        return availableCurrencies.first { $0.symbol == symbol }
    }
    
    func isConnected(for symbol: String) -> Bool {
        if case .connected = connectionStates[symbol] { return true }
        return false
    }
    

    deinit {
        disconnectWebSockets()
    }
}
