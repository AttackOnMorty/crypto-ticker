//
//  AppDelegate.swift
//  CryptoTicker
//
//  Created by Luke Mao on 5/2/2025.
//

import Cocoa
import SwiftUI
import os.log

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    private let webSocketManager = WebSocketManager()
    private let logger = Logger(subsystem: AppConfiguration.Logging.subsystem, category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Application launching...")
        setupStatusBarItem()
        setupMenu()
        setupObservers()
        startPriceUpdates()
        logger.info("Application launched successfully")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Application terminating...")
        webSocketManager.disconnectWebSockets()
    }

    private func setupStatusBarItem() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusBarItem.button else {
            logger.error("Failed to create status bar button")
            return
        }
        
        button.title = "Loading..."
        button.font = NSFont(name: AppConfiguration.UI.statusBarFont, size: AppConfiguration.UI.statusBarFontSize)

        button.action = #selector(statusBarButtonClicked)
        button.target = self
        
        logger.info("Status bar item created")
    }
    
    private func setupMenu() {
        statusBarItem.menu = createMenu()
    }
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMenu),
            name: NSNotification.Name("PriceUpdated"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMenu),
            name: NSNotification.Name("ConnectionStateChanged"),
            object: nil
        )
    }
    
    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(.separator())

        for currency in webSocketManager.availableCurrencies {
            let item = createCurrencyMenuItem(for: currency)
            menu.addItem(item)
        }
        
        menu.addItem(.separator())
        menu.addItem(createQuitMenuItem())
        
        return menu
    }
    
    private func createCurrencyMenuItem(for currency: CryptoCurrency) -> NSMenuItem {
        let price = webSocketManager.prices[currency.symbol] ?? "Loading..."
        let change = webSocketManager.priceChanges[currency.symbol] ?? "-"
        let isSelected = webSocketManager.selectedSymbols.contains(currency.symbol)
        let isConnected = webSocketManager.isConnected(for: currency.symbol)
        
        let title = formatCurrencyTitle(
            code: currency.code,
            name: currency.name,
            price: price,
            change: change,
            icon: currency.icon,
            isConnected: isConnected
        )
        
        let item = NSMenuItem(title: title, action: #selector(toggleCrypto(_:)), keyEquivalent: "")
        item.representedObject = currency.symbol
        item.state = isSelected ? .on : .off
        item.target = self

        item.attributedTitle = createAttributedTitle(
            code: currency.code,
            name: currency.name,
            price: price,
            change: change,
            icon: currency.icon,
            isConnected: isConnected
        )
        
        return item
    }
    
    private func createQuitMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        item.target = self
        return item
    }

    private func formatCurrencyTitle(code: String, name: String, price: String, change: String, icon: String, isConnected: Bool) -> String {
        let status = isConnected ? "●" : "○"
        return "\(status) \(icon) \(code) - \(name) - $\(price) (\(change))"
    }
    
    private func createAttributedTitle(code: String, name: String, price: String, change: String, icon: String, isConnected: Bool) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.tabStops = [
            NSTextTab(textAlignment: .left, location: 30, options: [:]),   // Status + Icon
            NSTextTab(textAlignment: .left, location: 80, options: [:]),   // Code
            NSTextTab(textAlignment: .left, location: 180, options: [:]),  // Name
            NSTextTab(textAlignment: .left, location: 280, options: [:]),  // Price
            NSTextTab(textAlignment: .left, location: 360, options: [:])   // Change
        ]
        
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: AppConfiguration.UI.menuFont, size: AppConfiguration.UI.menuFontSize) ?? NSFont.monospacedSystemFont(ofSize: AppConfiguration.UI.menuFontSize, weight: .regular),
            .paragraphStyle: paragraphStyle
        ]
        
        let statusColor: NSColor = isConnected ? .systemGreen : .systemRed
        let changeColor: NSColor = {
            if let changeValue = Double(change.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")) {
                return changeValue >= 0 ? .systemGreen : .systemRed
            }
            return .secondaryLabelColor
        }()
        
        let status = isConnected ? "●" : "○"
        let fullText = "\(status)\t\(icon) \(code)\t\(name)\t$\(price)\t\(formatPriceChange(change))"
        
        let attributedString = NSMutableAttributedString(string: fullText, attributes: baseAttributes)

        attributedString.addAttribute(.foregroundColor, value: statusColor, range: NSRange(location: 0, length: 1))

        if let changeRange = fullText.range(of: formatPriceChange(change)) {
            let nsRange = NSRange(changeRange, in: fullText)
            attributedString.addAttribute(.foregroundColor, value: changeColor, range: nsRange)
        }
        
        return attributedString
    }
    
    private func formatPriceChange(_ change: String) -> String {
        guard let changeValue = Double(change.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")) else {
            return change
        }
        return String(format: "%+.2f%%", changeValue)
    }

    private func startPriceUpdates() {
        Timer.scheduledTimer(withTimeInterval: AppConfiguration.UI.statusBarUpdateInterval, repeats: true) { [weak self] _ in
            self?.updateStatusBarTitle()
        }
    }
    
    private func updateStatusBarTitle() {
        DispatchQueue.main.async {
            guard let button = self.statusBarItem.button else { return }
            
            let displayText = self.createStatusBarDisplayText()
            button.title = displayText
        }
    }
    
    private func createStatusBarDisplayText() -> String {
        let selectedPrices = webSocketManager.selectedSymbols.compactMap { symbol -> String? in
            guard let currency = webSocketManager.getCurrency(for: symbol),
                  let price = webSocketManager.prices[symbol] else {
                return nil
            }
            
            let connectionStatus = webSocketManager.isConnected(for: symbol) ? "" : "!"
            return "\(currency.icon)\(connectionStatus) \(price)"
        }
        
        return selectedPrices.isEmpty ? "CRYPTO TICKER" : selectedPrices.joined(separator: " | ")
    }

    @objc private func statusBarButtonClicked() {}
    
    @objc private func toggleCrypto(_ sender: NSMenuItem) {
        guard let symbol = sender.representedObject as? String else {
            logger.error("Invalid symbol in menu item")
            return
        }
        
        webSocketManager.toggleCryptoSelection(symbol)
    }
    
    @objc private func updateMenu() {
        DispatchQueue.main.async {
            self.statusBarItem.menu = self.createMenu()
        }
    }
    
    @objc private func quitApp() {
        logger.info("Quit requested")
        webSocketManager.disconnectWebSockets()
        NSApplication.shared.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        Task {
            await webSocketManager.fetchAllCryptoPrices()
        }
    }
    
    func menuDidClose(_ menu: NSMenu) {}
}
