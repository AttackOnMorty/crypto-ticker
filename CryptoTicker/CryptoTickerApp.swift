//
//  CryptoTickerApp.swift
//  CryptoTicker
//
//  Created by Luke Mao on 5/2/2025.
//

import SwiftUI
import os.log

@main
struct CryptoTickerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let logger = Logger(subsystem: AppConfiguration.Logging.subsystem, category: "CryptoTickerApp")

    init() {
        guard AppConfiguration.validate() else {
            logger.error("Configuration validation failed")
            fatalError("Invalid app configuration")
        }

        logger.info("CryptoTicker app initialized successfully")
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
