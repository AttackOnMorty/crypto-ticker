//
//  SymbolSearch.swift
//  CryptoTicker
//

import Foundation

/// Local, case-insensitive search over the cached exchangeInfo list. Binance has no
/// server-side symbol search, so the client filters the full list on each keystroke.
/// Prefix matches on the base asset rank above substring matches.
enum SymbolSearch {
    static func match(query: String, in symbols: [TradableSymbol]) -> [TradableSymbol] {
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard !q.isEmpty else { return [] }
        let prefix = symbols.filter { $0.baseAsset.uppercased().hasPrefix(q) }
        let substring = symbols.filter {
            !$0.baseAsset.uppercased().hasPrefix(q) &&
            ($0.baseAsset.uppercased().contains(q) || $0.symbol.uppercased().contains(q))
        }
        return prefix + substring
    }
}
