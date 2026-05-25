//
//  DisplayText.swift
//  CryptoTicker
//
//  Pure builders for the menu-bar title and menu-row text. Foundation-only so they are
//  testable without AppKit.
//

import Foundation

/// Builds a menu-row's attributed-string text together with the exact ranges to colour,
/// computed by construction. Colouring by explicit range (rather than searching for the
/// token) means the placeholder "—" can never make the change colour land on the price.
enum MenuRowText {
    struct Row {
        let text: String
        let statusRange: NSRange
        let changeRange: NSRange
    }

    static func make(glyph: String, icon: String, code: String, name: String, price: String, change: String) -> Row {
        let text = "\(glyph)\t\(icon) \(code)\t\(name)\t$\(price)\t\(change)"
        let fullLength = (text as NSString).length
        let changeLength = (change as NSString).length
        return Row(
            text: text,
            statusRange: NSRange(location: 0, length: (glyph as NSString).length),
            changeRange: NSRange(location: fullLength - changeLength, length: changeLength)
        )
    }
}
