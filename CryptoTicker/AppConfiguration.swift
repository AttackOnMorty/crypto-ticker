//
//  AppConfiguration.swift
//  CryptoTicker
//
//  Created by Luke Mao on 5/2/2025.
//

import Foundation

struct AppConfiguration {
    struct API {
        static let binanceBaseURL = "https://api.binance.com/api/v3"
        static let binanceWebSocketURL = "wss://stream.binance.com:9443/ws"
    }

    struct UI {
        static let appTitle = "CRYPTO TICKER"
        static let loadingText = "Loading..."
        static let statusBarUpdateInterval: TimeInterval = 1.0
        static let monospaceFont = "Menlo"
        static let monospaceFontSize: CGFloat = 12.0
        /// Skip the all-currencies REST refetch if the menu reopened within this window.
        static let menuFetchDebounce: TimeInterval = 10
        /// Left tab-stop column positions for the aligned menu rows.
        static let menuTabStops: [CGFloat] = [30, 80, 180, 280, 360]
    }

    struct WebSocket {
        static let reconnectDelay: TimeInterval = 5.0
        static let maxReconnectDelay: TimeInterval = 60.0
        /// Send a keepalive ping this often to detect a half-open connection.
        static let pingInterval: TimeInterval = 30.0
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
}
