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

    private lazy var panelController = TickerPanelController(symbols: webSocketManager.availableSymbols)
    private var statusBarTimer: Timer?
    private var lastStatusTitle: StatusBarText.Title?
    private var lastPanelFetch: Date?

    /// When the data last changed, for the panel's footer.
    private var lastDataChange = Date()

    override init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Application launching...")
        setupStatusBarItem()
        setupPanel()
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

        button.attributedTitle = attributedStatusTitle(StatusBarText.make(items: []))
        button.action = #selector(statusBarButtonClicked)
        button.target = self
        // Act on press, the way a menu does. On mouse *up* the app's first click while it
        // is inactive is swallowed by activation, so the panel would need two clicks to
        // open — which is what `NSStatusItem.menu` used to hide from us.
        button.sendAction(on: [.leftMouseDown])

        logger.info("Status bar item created")
    }

    private func setupPanel() {
        panelController.contentView.delegate = self
        panelController.onOpen = { [weak self] in self?.panelWillOpen() }
        panelController.onClose = { [weak self] in self?.webSocketManager.isPanelVisible = false }
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

    // MARK: - Status bar

    private func startPriceUpdates() {
        statusBarTimer = Timer.scheduledTimer(withTimeInterval: AppConfiguration.UI.statusBarUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusBarTitle()
            }
        }
    }

    private func updateStatusBarTitle() {
        guard let button = statusBarItem.button else { return }

        let title = createStatusBarTitle()
        // F9: only touch the UI when something actually changed. Colour is part of the
        // title here, so the comparison covers the ranges too.
        guard title != lastStatusTitle else { return }
        lastStatusTitle = title
        button.attributedTitle = attributedStatusTitle(title)
    }

    private func createStatusBarTitle() -> StatusBarText.Title {
        let items = webSocketManager.selectedSymbols.compactMap { symbol -> StatusBarText.Item? in
            guard let price = webSocketManager.prices[symbol] else { return nil }
            return StatusBarText.Item(
                code: SymbolCatalog.displayCode(for: symbol),
                price: price,
                isLive: webSocketManager.isConnected(for: symbol)
            )
        }
        return StatusBarText.make(items: items)
    }

    /// Two greys and no glyphs: the code recedes, the number reads, and an item with no
    /// live socket dims out whole.
    private func attributedStatusTitle(_ title: StatusBarText.Title) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: title.text,
            attributes: [
                .font: NothingTheme.data(size: NothingTheme.TypeSize.menuBar),
                .foregroundColor: NothingTheme.Palette.textSecondary,
            ]
        )
        for range in title.valueRanges {
            result.addAttribute(.foregroundColor, value: NothingTheme.Palette.textDisplay, range: range)
        }
        for range in title.staleRanges {
            result.addAttribute(.foregroundColor, value: NothingTheme.Palette.textDisabled, range: range)
        }
        return result
    }

    // MARK: - Panel

    private func panelWillOpen() {
        webSocketManager.isPanelVisible = true
        refreshPanel()

        let now = Date()
        if let last = lastPanelFetch, now.timeIntervalSince(last) < AppConfiguration.UI.panelFetchDebounce { return }
        lastPanelFetch = now
        Task { @MainActor in
            await webSocketManager.fetchAllPrices()
            lastDataChange = Date()
            refreshPanel()
        }
    }

    private func refreshPanel() {
        panelController.contentView.update(with: makeSnapshot())
    }

    private func makeSnapshot() -> PanelSnapshot {
        return PanelSnapshot(
            coins: webSocketManager.availableSymbols.map(coin(for:)),
            updated: "UPDATED \(Self.timeFormatter.string(from: lastDataChange))"
        )
    }

    private func coin(for symbol: String) -> PanelSnapshot.Coin {
        let isSelected = webSocketManager.selectedSymbols.contains(symbol)
        return PanelSnapshot.Coin(
            symbol: symbol,
            pair: PanelText.pair(for: symbol),
            price: webSocketManager.prices[symbol] ?? PriceFormatter.placeholder,
            change: PanelText.change(fromRaw: webSocketManager.priceChanges[symbol] ?? ""),
            status: PanelText.status(isSelected: isSelected, state: webSocketManager.connectionStates[symbol]),
            isSelected: isSelected
        )
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    // MARK: - Events

    @objc private func statusBarButtonClicked() {
        guard let button = statusBarItem.button else { return }
        panelController.toggle(relativeTo: button)
    }

    /// Live data changed. Only the open panel needs refreshing; when it is closed the 1 Hz
    /// status-bar timer already covers the visible UI, so we do nothing (F6).
    @objc private func dataDidChange(_ notification: Notification) {
        lastDataChange = Date()
        guard webSocketManager.isPanelVisible else { return }
        refreshPanel()
    }
}

extension AppDelegate: TickerPanelViewDelegate {
    func panelView(_ view: TickerPanelView, didToggle symbol: String) {
        webSocketManager.toggleCryptoSelection(symbol)
        refreshPanel()
    }

    func panelViewDidRequestQuit(_ view: TickerPanelView) {
        logger.info("Quit requested")
        statusBarTimer?.invalidate()
        webSocketManager.disconnectWebSockets()
        NSApplication.shared.terminate(nil)
    }
}
