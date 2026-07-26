//
//  AppConfiguration.swift
//  Tickbyte
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
        /// Bracketed system text, not a spinner or a skeleton.
        static let loadingText = "[LOADING]"
        static let statusBarUpdateInterval: TimeInterval = 1.0
        /// Skip the price refetch if the panel reopened within this window.
        static let panelFetchDebounce: TimeInterval = 10
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
        static let subsystem = "attackonmorty.tickbyte"
    }

    struct Defaults {
        static let selectedCryptos = ["btcusdt", "ethusdt"]
    }
}
