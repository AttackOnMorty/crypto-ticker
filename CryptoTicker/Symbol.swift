//
//  Symbol.swift
//  CryptoTicker
//

import Foundation

/// The fixed set of coins the app supports, and the helpers for validating and
/// displaying them. Membership in `supported` is the security guard: symbols are
/// interpolated unescaped into the WebSocket URL path, so a tampered plist must not
/// be able to inject an arbitrary segment.
enum SymbolCatalog {
    static let supported = ["btcusdt", "ethusdt"]

    /// Keeps only supported symbols, preserving order and dropping duplicates.
    /// Duplicates matter: two menu rows would share one `currencyMenuItems` entry,
    /// leaving one row permanently stale.
    static func validSymbols(from raw: [String]) -> [String] {
        var seen = Set<String>()
        return raw.filter { supported.contains($0) && seen.insert($0).inserted }
    }

    /// "btcusdt" -> "BTC". Strips the trailing "usdt" quote and uppercases the base.
    static func displayCode(for symbol: String) -> String {
        let base = symbol.hasSuffix("usdt") ? String(symbol.dropLast(4)) : symbol
        return base.uppercased()
    }
}
