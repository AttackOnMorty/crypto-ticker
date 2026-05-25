//
//  CryptoTickerApp.swift
//  CryptoTicker
//
//  Created by Luke Mao on 5/2/2025.
//

import SwiftUI

@main
struct CryptoTickerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
