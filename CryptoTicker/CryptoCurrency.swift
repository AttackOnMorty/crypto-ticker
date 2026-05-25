//
//  CryptoCurrency.swift
//  CryptoTicker
//

import Foundation

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
