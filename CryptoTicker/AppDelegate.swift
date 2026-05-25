//
//  AppDelegate.swift
//  CryptoTicker
//
//  Created by Luke Mao on 5/2/2025.
//

import Cocoa
import SwiftUI
import os.log

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    private let webSocketManager = WebSocketManager()
    private let logger = Logger(subsystem: AppConfiguration.Logging.subsystem, category: "AppDelegate")

    /// Persistent menu items keyed by symbol, refreshed in place rather than rebuilt.
    private var currencyMenuItems: [String: NSMenuItem] = [:]
    private var lastMenuFetch: Date?
    private var statusBarTimer: Timer?
    private var lastStatusTitle: String?

    /// Skip the all-currencies REST refetch if the menu was opened again within this window.
    private let menuFetchDebounce: TimeInterval = 10
    private static let menuTabStops: [CGFloat] = [30, 80, 180, 280, 360]

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
        statusBarTimer?.invalidate()
        webSocketManager.disconnectWebSockets()
    }

    private func setupStatusBarItem() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusBarItem.button else {
            logger.error("Failed to create status bar button")
            return
        }

        button.title = AppConfiguration.UI.loadingText
        button.font = NSFont(name: AppConfiguration.UI.monospaceFont, size: AppConfiguration.UI.monospaceFontSize)

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
            selector: #selector(dataDidChange),
            name: .priceUpdated,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dataDidChange),
            name: .connectionStateChanged,
            object: nil
        )
    }

    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(.separator())

        currencyMenuItems.removeAll()
        for currency in webSocketManager.availableCurrencies {
            let item = NSMenuItem(title: "", action: #selector(toggleCrypto(_:)), keyEquivalent: "")
            item.representedObject = currency.symbol
            item.target = self
            currencyMenuItems[currency.symbol] = item
            configureMenuItem(item, for: currency)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(createQuitMenuItem())

        return menu
    }

    /// Updates the persistent menu items' titles/state from current data, in place — no
    /// menu rebuild and no reassigning `statusBarItem.menu` (F5/F6).
    private func refreshMenuItems() {
        for currency in webSocketManager.availableCurrencies {
            guard let item = currencyMenuItems[currency.symbol] else { continue }
            configureMenuItem(item, for: currency)
        }
    }

    private func configureMenuItem(_ item: NSMenuItem, for currency: CryptoCurrency) {
        let price = webSocketManager.prices[currency.symbol] ?? AppConfiguration.UI.loadingText
        let change = webSocketManager.priceChanges[currency.symbol] ?? ""
        let isConnected = webSocketManager.isConnected(for: currency.symbol)

        item.state = webSocketManager.selectedSymbols.contains(currency.symbol) ? .on : .off
        item.attributedTitle = attributedMenuTitle(for: currency, price: price, change: change, isConnected: isConnected)
    }

    private func createQuitMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        item.target = self
        return item
    }

    private func statusGlyph(isConnected: Bool) -> String {
        isConnected ? "●" : "○"
    }

    private func attributedMenuTitle(for currency: CryptoCurrency, price: String, change: String, isConnected: Bool) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.tabStops = Self.menuTabStops.map { NSTextTab(textAlignment: .left, location: $0, options: [:]) }

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: AppConfiguration.UI.monospaceFont, size: AppConfiguration.UI.monospaceFontSize) ?? NSFont.monospacedSystemFont(ofSize: AppConfiguration.UI.monospaceFontSize, weight: .regular),
            .paragraphStyle: paragraphStyle
        ]

        let statusColor: NSColor = isConnected ? .systemGreen : .systemRed
        let changeColor: NSColor = {
            guard let value = PriceFormatter.percentValue(change) else { return .secondaryLabelColor }
            return value >= 0 ? .systemGreen : .systemRed
        }()

        let row = MenuRowText.make(
            glyph: statusGlyph(isConnected: isConnected),
            icon: currency.icon,
            code: currency.code,
            name: currency.name,
            price: price,
            change: PriceFormatter.percent(change)
        )

        let attributedString = NSMutableAttributedString(string: row.text, attributes: baseAttributes)
        attributedString.addAttribute(.foregroundColor, value: statusColor, range: row.statusRange)
        attributedString.addAttribute(.foregroundColor, value: changeColor, range: row.changeRange)

        return attributedString
    }

    private func startPriceUpdates() {
        statusBarTimer = Timer.scheduledTimer(withTimeInterval: AppConfiguration.UI.statusBarUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusBarTitle()
            }
        }
    }

    private func updateStatusBarTitle() {
        guard let button = statusBarItem.button else { return }

        let displayText = createStatusBarDisplayText()
        // F9: only touch the UI when the text actually changed.
        guard displayText != lastStatusTitle else { return }
        lastStatusTitle = displayText
        button.title = displayText
    }

    private func createStatusBarDisplayText() -> String {
        let items = webSocketManager.selectedSymbols.compactMap { symbol -> StatusBarText.Item? in
            guard let currency = webSocketManager.getCurrency(for: symbol),
                  let price = webSocketManager.prices[symbol] else {
                return nil
            }
            return StatusBarText.Item(
                icon: currency.icon,
                price: price,
                indicator: StatusBarText.indicator(for: webSocketManager.connectionStates[symbol])
            )
        }
        return StatusBarText.make(items: items)
    }

    @objc private func statusBarButtonClicked() {}

    @objc private func toggleCrypto(_ sender: NSMenuItem) {
        guard let symbol = sender.representedObject as? String else {
            logger.error("Invalid symbol in menu item")
            return
        }

        webSocketManager.toggleCryptoSelection(symbol)
        refreshMenuItems()
    }

    /// Live data changed. Only the open menu needs refreshing in place; when it's closed
    /// the 1 Hz status-bar timer already covers the visible UI, so we do nothing (F6).
    @objc private func dataDidChange() {
        guard webSocketManager.isMenuVisible else { return }
        refreshMenuItems()
    }

    @objc private func quitApp() {
        logger.info("Quit requested")
        statusBarTimer?.invalidate()
        webSocketManager.disconnectWebSockets()
        NSApplication.shared.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        webSocketManager.isMenuVisible = true
        refreshMenuItems()

        // F8: only refetch all currencies if the cache is stale.
        let now = Date()
        if let last = lastMenuFetch, now.timeIntervalSince(last) < menuFetchDebounce {
            return
        }
        lastMenuFetch = now
        Task { @MainActor in
            await webSocketManager.fetchAllCryptoPrices()
            refreshMenuItems()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        webSocketManager.isMenuVisible = false
    }
}
