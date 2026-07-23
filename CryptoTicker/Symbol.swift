//
//  Symbol.swift
//  CryptoTicker
//

import Foundation

/// A Binance spot symbol tradable against USDT, as surfaced by `exchangeInfo`.
struct TradableSymbol: Equatable {
    let symbol: String     // lowercase stream form, e.g. "solusdt"
    let baseAsset: String  // e.g. "SOL"
}

/// Symbol validation and display. `isValid` is the security boundary: the symbol is
/// interpolated unescaped into the WebSocket URL path, so this regex (not a whitelist)
/// is what blocks URL injection.
enum SymbolFormat {
    static func isValid(_ symbol: String) -> Bool {
        symbol.range(of: "^[a-z0-9]{2,20}usdt$", options: .regularExpression) != nil
    }

    /// "solusdt" -> "SOL". Strips the trailing "usdt" quote and uppercases the base.
    static func displayCode(for symbol: String) -> String {
        let base = symbol.hasSuffix("usdt") ? String(symbol.dropLast(4)) : symbol
        return base.uppercased()
    }
}
