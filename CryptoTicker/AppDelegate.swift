//
//  AppDelegate.swift
//  CryptoTicker
//
//  Created by Luke Mao on 5/2/2025.
//

import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    private let webSocketManager = WebSocketManager()
    private let updateInterval: TimeInterval = 1.0
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        setupMenu()
        setupObservers()
        startPriceUpdates()
    }
    
    private func setupStatusBarItem() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem.button?.title = "Loading..."
    }
    
    private func setupMenu() {
        statusBarItem.menu = createMenu()
    }
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(updateMenu), name: NSNotification.Name("PriceUpdated"), object: nil)
    }
    
    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        
        for (code, name, symbol, _) in webSocketManager.cryptoPairs {
            let price = webSocketManager.prices[symbol] ?? "Loading..."
            let change = formatPriceChange(webSocketManager.priceChanges[symbol] ?? "-")
            
            let formattedText = "\(code)\t\(name)\t$\(price)\t"
            let item = NSMenuItem(title: formattedText, action: #selector(toggleCrypto(_:)), keyEquivalent: "")
            item.representedObject = symbol
            item.state = webSocketManager.selectedSymbols.contains(symbol) ? .on : .off
            item.attributedTitle = createAttributedText(for: formattedText, change: change)
            
            menu.addItem(item)
        }
        
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        
        return menu
    }
    
    private func createAttributedText(for text: String, change: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.tabStops = [
            NSTextTab(textAlignment: .left, location: 80, options: [:]),
            NSTextTab(textAlignment: .left, location: 200, options: [:]),
            NSTextTab(textAlignment: .left, location: 270, options: [:])
        ]
        
        let fullString = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .paragraphStyle: paragraphStyle
        ])
        
        let changeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let changeString = NSAttributedString(string: change, attributes: changeAttributes)
        fullString.append(changeString)
        
        return fullString
    }
    
    private func formatPriceChange(_ change: String) -> String {
        guard let changeValue = Double(change.replacingOccurrences(of: "%", with: "")) else { return change }
        return String(format: "%+5.1f%%", changeValue)
    }
    
    private func startPriceUpdates() {
        Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updateStatusBarTitle()
        }
    }
    
    private func updateStatusBarTitle() {
        DispatchQueue.main.async {
            guard let button = self.statusBarItem.button else { return }
            let prices = self.webSocketManager.selectedSymbols.compactMap { symbol in
                guard let cryptoInfo = self.webSocketManager.cryptoPairs.first(where: { $0.2 == symbol }) else { return nil }
                let shortCode = cryptoInfo.3
                return self.webSocketManager.prices[symbol].map { "\(shortCode) \($0)" }
            }.joined(separator: " ")
            
            button.title = prices.isEmpty ? "CRYPTO TICKER" : prices
            button.font = NSFont(name: "Menlo", size: 12)
        }
    }
    
    @objc private func toggleCrypto(_ sender: NSMenuItem) {
        if let symbol = sender.representedObject as? String {
            webSocketManager.toggleCryptoSelection(symbol)
            updateMenu()
        }
    }
    
    @objc private func updateMenu() {
        DispatchQueue.main.async { self.statusBarItem.menu = self.createMenu() }
    }
    
    @objc private func quitApp() {
        webSocketManager.disconnectWebSockets()
        NSApplication.shared.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        webSocketManager.fetchAllCryptoPrices()
    }
}
