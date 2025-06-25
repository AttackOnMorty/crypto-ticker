//
//  AppConfiguration.swift
//  CryptoTicker
//
//  Created by Luke Mao on 5/2/2025.
//

import Foundation

struct AppConfiguration {
    
    // MARK: - App Information
    static let appName = "CryptoTicker"
    static let version = "1.0.0"
    static let bundleIdentifier = "com.cryptoticker.app"
    
    // MARK: - API Configuration
    struct API {
        static let binanceBaseURL = "https://api.binance.com/api/v3"
        static let binanceWebSocketURL = "wss://stream.binance.com:9443/ws"
        static let requestTimeout: TimeInterval = 10.0
    }
    
    // MARK: - UI Configuration
    struct UI {
        static let statusBarUpdateInterval: TimeInterval = 1.0
        static let menuFont = "Menlo"
        static let menuFontSize: CGFloat = 12.0
        static let statusBarFont = "Menlo"
        static let statusBarFontSize: CGFloat = 12.0
    }
    
    // MARK: - WebSocket Configuration
    struct WebSocket {
        static let reconnectDelay: TimeInterval = 5.0
        static let maxReconnectAttempts = 3
        static let heartbeatInterval: TimeInterval = 30.0
    }
    
    // MARK: - User Defaults Keys
    struct UserDefaultsKeys {
        static let selectedCryptos = "selectedCryptos"
        static let lastUpdateTime = "lastUpdateTime"
        static let appLaunchCount = "appLaunchCount"
    }
    
    // MARK: - Logging
    struct Logging {
        static let subsystem = "com.cryptoticker.app"
        static let categories = [
            "AppDelegate",
            "WebSocketManager",
            "Configuration"
        ]
    }
    
    // MARK: - Default Settings
    struct Defaults {
        static let selectedCryptos = ["btcusdt"]
        static let maxDisplayedCryptos = 5
        static let priceUpdateInterval: TimeInterval = 2.0
    }
    
    // MARK: - Validation
    static func validate() -> Bool {
        // Validate URLs
        guard URL(string: API.binanceBaseURL) != nil else {
            print("Invalid Binance API URL")
            return false
        }
        
        guard URL(string: API.binanceWebSocketURL) != nil else {
            print("Invalid Binance WebSocket URL")
            return false
        }
        
        // Validate intervals
        guard UI.statusBarUpdateInterval > 0 else {
            print("Invalid status bar update interval")
            return false
        }
        
        return true
    }
} 