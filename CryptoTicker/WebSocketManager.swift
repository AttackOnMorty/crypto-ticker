import Foundation

class WebSocketManager: ObservableObject {
    @Published var prices: [String: String] = [:]
    @Published var selectedSymbols: [String] = []
    @Published var priceChanges: [String: String] = [:]

    private var webSocketTasks: [String: URLSessionWebSocketTask] = [:]
    private let urlSession = URLSession(configuration: .default)
    private let userDefaultsKey = "selectedCryptos"
    
    let cryptoPairs = [
        ("BTC", "Bitcoin", "btcusdt", "₿"),
        ("ETH", "Ethereum", "ethusdt", "Ξ"),
        ("XRP", "XRP", "xrpusdt", "✕"),
        ("SOL", "Solana", "solusdt", "S"),
        ("BNB", "BNB", "bnbusdt", "B"),
        ("DOGE", "Dogecoin", "dogeusdt", "Ɖ"),
        ("ADA", "Cardano", "adausdt", "₳"),
        ("TRX", "TRON", "trxusdt", "T"),
        ("LINK", "Chainlink", "linkusdt", "L"),
        ("AVAX", "Avalanche", "avaxusdt", "A"),
        ("TRUMP", "Official Trump", "trumpusdt", "TRU")
    ]
    
    init() {
        loadSelectedCryptos()
        fetchAllCryptoPrices()
        connectWebSockets()
    }
    
    private func loadSelectedCryptos() {
        selectedSymbols = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] ?? ["btcusdt"]
    }
    
    private func saveSelectedCryptos() {
        UserDefaults.standard.set(selectedSymbols, forKey: userDefaultsKey)
    }
    
    func fetchAllCryptoPrices() {
        cryptoPairs.forEach { fetchPrice(for: $0.2) }
    }
    
    private func fetchPrice(for symbol: String) {
        guard let url = URL(string: "https://api.binance.com/api/v3/ticker/24hr?symbol=\(symbol.uppercased())") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let priceStr = json["lastPrice"] as? String,
                  let changeStr = json["priceChangePercent"] as? String else { return }
            
            DispatchQueue.main.async {
                self.prices[symbol] = self.formatPrice(priceStr)
                self.priceChanges[symbol] = self.formatPercent(changeStr) + "%"
                NotificationCenter.default.post(name: NSNotification.Name("PriceUpdated"), object: nil)
            }
        }.resume()
    }
    
    func connectWebSockets() {
        disconnectWebSockets()
        selectedSymbols.forEach { connectWebSocket(for: $0) }
    }
    
    private func connectWebSocket(for symbol: String) {
        guard let url = URL(string: "wss://stream.binance.com:9443/ws/\(symbol)@trade") else { return }
        
        let task = urlSession.webSocketTask(with: url)
        webSocketTasks[symbol] = task
        task.resume()
        receiveMessage(for: symbol)
    }
    
    private func receiveMessage(for symbol: String) {
        webSocketTasks[symbol]?.receive { [weak self] result in
            guard let self = self else { return }
            
            if case .success(let message) = result, case .string(let text) = message {
                self.handleIncomingData(text, for: symbol)
            }
            
            self.receiveMessage(for: symbol)
        }
    }
    
    private func handleIncomingData(_ text: String, for symbol: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let priceStr = json["p"] as? String else { return }
        
        DispatchQueue.main.async {
            self.prices[symbol] = self.formatPrice(priceStr)
            NotificationCenter.default.post(name: NSNotification.Name("PriceUpdated"), object: nil)
        }
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
    
    func disconnectWebSockets() {
        webSocketTasks.values.forEach { $0.cancel() }
        webSocketTasks.removeAll()
    }
    
    private func formatPrice(_ price: String) -> String {
        guard let priceDouble = Double(price) else { return price }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        
        formatter.maximumFractionDigits = priceDouble >= 100 ? 0 : priceDouble >= 1 ? 1 : priceDouble >= 0.1 ? 3 : 8
        
        return formatter.string(from: NSNumber(value: priceDouble)) ?? price
    }
    
    private func formatPercent(_ percent: String) -> String {
        guard let percentDouble = Double(percent) else { return percent }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: percentDouble)) ?? percent
    }
}
