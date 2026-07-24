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
    private var statusBarTimer: Timer?
    private var lastStatusTitle: String?
    private var lastMenuFetch: Date?

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
            selector: #selector(dataDidChange(_:)),
            name: .priceUpdated,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dataDidChange(_:)),
            name: .connectionStateChanged,
            object: nil
        )
    }

    /// Builds one row per supported symbol, once — the list is fixed, so unlike the old
    /// search-driven selection there is nothing to rebuild on menu open. Mutating menu
    /// structure inside `menuWillOpen` would violate AppKit's documented contract.
    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        for symbol in webSocketManager.availableSymbols {
            let item = NSMenuItem(title: "", action: #selector(toggleCrypto(_:)), keyEquivalent: "")
            item.representedObject = symbol
            item.target = self
            currencyMenuItems[symbol] = item
            configureMenuItem(item, forSymbol: symbol)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(createQuitMenuItem())
        return menu
    }

    /// Updates the persistent menu items' titles/state from current data, in place — no
    /// menu rebuild and no reassigning `statusBarItem.menu` (F5/F6). Iterates every
    /// supported symbol (not just selected) so a hidden coin's row stays current too.
    private func refreshMenuItems() {
        for symbol in webSocketManager.availableSymbols {
            guard let item = currencyMenuItems[symbol] else { continue }
            configureMenuItem(item, forSymbol: symbol)
        }
    }

    /// Refreshes a single row in place (F5) — used for the per-trade price path, which names
    /// the one symbol that changed instead of rebuilding all rows.
    private func refreshMenuItem(for symbol: String) {
        guard let item = currencyMenuItems[symbol] else { return }
        configureMenuItem(item, forSymbol: symbol)
    }

    private func configureMenuItem(_ item: NSMenuItem, forSymbol symbol: String) {
        let price = webSocketManager.prices[symbol] ?? AppConfiguration.UI.loadingText
        let change = webSocketManager.priceChanges[symbol] ?? ""
        let isConnected = webSocketManager.isConnected(for: symbol)
        item.attributedTitle = attributedMenuTitle(forSymbol: symbol, price: price, change: change, isConnected: isConnected)
        item.state = webSocketManager.selectedSymbols.contains(symbol) ? .on : .off
    }

    private func createQuitMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        item.target = self
        return item
    }

    private func statusGlyph(isConnected: Bool) -> String {
        isConnected ? "●" : "○"
    }

    /// Font and tab-stop layout are identical for every row and never change, so build them
    /// once instead of on each per-trade refresh (F6). Only the per-row colours vary.
    private static let menuBaseAttributes: [NSAttributedString.Key: Any] = {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.tabStops = AppConfiguration.UI.menuTabStops.map { NSTextTab(textAlignment: .left, location: $0, options: [:]) }
        let font = NSFont(name: AppConfiguration.UI.monospaceFont, size: AppConfiguration.UI.monospaceFontSize)
            ?? NSFont.monospacedSystemFont(ofSize: AppConfiguration.UI.monospaceFontSize, weight: .regular)
        return [.font: font, .paragraphStyle: paragraphStyle]
    }()

    private func attributedMenuTitle(forSymbol symbol: String, price: String, change: String, isConnected: Bool) -> NSAttributedString {
        let statusColor: NSColor = isConnected ? .systemGreen : .systemRed
        let changeColor: NSColor = {
            guard let value = PriceFormatter.percentValue(change) else { return .secondaryLabelColor }
            return value >= 0 ? .systemGreen : .systemRed
        }()

        let row = MenuRowText.make(
            glyph: statusGlyph(isConnected: isConnected),
            code: SymbolCatalog.displayCode(for: symbol),
            price: price,
            change: PriceFormatter.percent(change)
        )

        let attributedString = NSMutableAttributedString(string: row.text, attributes: Self.menuBaseAttributes)
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
            guard let price = webSocketManager.prices[symbol] else { return nil }
            return StatusBarText.Item(
                code: SymbolCatalog.displayCode(for: symbol),
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
    /// A `.priceUpdated` notification names its symbol, so only that row is refreshed (F5);
    /// `.connectionStateChanged` carries no symbol and refreshes all rows.
    @objc private func dataDidChange(_ notification: Notification) {
        guard webSocketManager.isMenuVisible else { return }
        if let symbol = notification.object as? String {
            refreshMenuItem(for: symbol)
        } else {
            refreshMenuItems()
        }
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

        let now = Date()
        if let last = lastMenuFetch, now.timeIntervalSince(last) < AppConfiguration.UI.menuFetchDebounce { return }
        lastMenuFetch = now
        Task { @MainActor in
            await webSocketManager.fetchAllPrices()
            refreshMenuItems()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        webSocketManager.isMenuVisible = false
    }
}
