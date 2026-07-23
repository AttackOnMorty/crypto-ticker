//
//  ExchangeInfo.swift
//  CryptoTicker
//

import Foundation

/// Decodes Binance `exchangeInfo` into the USDT-quoted, currently-tradable symbols we offer
/// for search. Filtering to `status == "TRADING"` skips halted/delisting (`BREAK`) markets;
/// there is no server-side quote filter, so USDT is filtered here.
enum ExchangeInfo {
    private struct Response: Decodable {
        struct Symbol: Decodable {
            let symbol: String
            let status: String
            let baseAsset: String
            let quoteAsset: String
        }
        let symbols: [Symbol]
    }

    static func parse(_ data: Data) -> [TradableSymbol] {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return response.symbols
            .filter { $0.status == "TRADING" && $0.quoteAsset == "USDT" }
            .map { TradableSymbol(symbol: $0.symbol.lowercased(), baseAsset: $0.baseAsset) }
    }
}
