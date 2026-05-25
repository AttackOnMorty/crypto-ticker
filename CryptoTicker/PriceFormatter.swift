//
//  PriceFormatter.swift
//  CryptoTicker
//

import Foundation

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
