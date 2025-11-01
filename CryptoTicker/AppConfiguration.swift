//
//  AppConfiguration.swift
//  CryptoTicker
//
//  Created by Luke Mao on 5/2/2025.
//

import Foundation

struct AppConfiguration {
    static let appName = "CryptoTicker"
    static let version = "1.0.0"
    static let bundleIdentifier = "com.cryptoticker.app"

    struct API {
        static let binanceBaseURL = "https://api.binance.com/api/v3"
        static let binanceWebSocketURL = "wss://stream.binance.com:9443/ws"
    }

    struct UI {
        static let statusBarUpdateInterval: TimeInterval = 1.0
        static let menuFont = "Menlo"
        static let menuFontSize: CGFloat = 12.0
        static let statusBarFont = "Menlo"
        static let statusBarFontSize: CGFloat = 12.0
    }

    struct WebSocket {
        static let reconnectDelay: TimeInterval = 5.0
    }

    struct UserDefaultsKeys {
        static let selectedCryptos = "selectedCryptos"
    }

    struct Logging {
        static let subsystem = "com.cryptoticker.app"
    }

    struct Defaults {
        static let selectedCryptos = ["btcusdt"]
    }

    static func validate() -> Bool {
        guard URL(string: API.binanceBaseURL) != nil,
              URL(string: API.binanceWebSocketURL) != nil,
              UI.statusBarUpdateInterval > 0 else {
            return false
        }
        return true
    }
} 