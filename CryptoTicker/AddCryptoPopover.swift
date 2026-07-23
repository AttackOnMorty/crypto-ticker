//
//  AddCryptoPopover.swift
//  CryptoTicker
//

import Cocoa

/// Search + add/remove surface shown in an NSPopover. Added symbols show a green ✓ (click
/// removes); search results show + (click adds). Binance has no server-side search, so on
/// first appearance it loads the exchangeInfo list once and filters locally per keystroke.
@MainActor
final class AddCryptoPopoverController: NSViewController {
    private let manager: WebSocketManager
    private let onChange: () -> Void
    private let searchField = NSSearchField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let rowsStack = NSStackView()

    init(manager: WebSocketManager, onChange: @escaping () -> Void) {
        self.manager = manager
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 320))

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search crypto (e.g. SOL)"
        searchField.target = self
        searchField.action = #selector(searchChanged)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 2
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(rowsStack)
        scroll.documentView = doc

        container.addSubview(searchField)
        container.addSubview(statusLabel)
        container.addSubview(scroll)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),

            statusLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),

            scroll.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),

            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),

            rowsStack.topAnchor.constraint(equalTo: doc.topAnchor),
            rowsStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 4),
            rowsStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -4),
            rowsStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])

        view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(searchField)
        reload()
        Task { @MainActor in
            await manager.loadTradableSymbolsIfNeeded()
            reload()
        }
    }

    @objc private func searchChanged() {
        if manager.exchangeInfoState == .idle || manager.exchangeInfoState == .failed {
            Task { @MainActor in
                await manager.loadTradableSymbolsIfNeeded()
                reload()
            }
        }
        reload()
    }

    private func reload() {
        rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)

        if query.isEmpty {
            statusLabel.stringValue = manager.selectedSymbols.isEmpty
                ? "No cryptos yet — search to add."
                : "Your cryptos:"
            for symbol in manager.selectedSymbols {
                rowsStack.addArrangedSubview(makeRow(symbol: symbol, added: true))
            }
            return
        }

        switch manager.exchangeInfoState {
        case .idle, .loading:
            statusLabel.stringValue = "Loading symbols…"
        case .failed:
            statusLabel.stringValue = "Couldn't load symbols. Edit search to retry."
        case .loaded:
            let results = SymbolSearch.match(query: query, in: manager.tradableSymbols)
            statusLabel.stringValue = results.isEmpty ? "No matches." : "Results:"
            for ts in results.prefix(50) {
                let added = manager.selectedSymbols.contains(ts.symbol)
                rowsStack.addArrangedSubview(makeRow(symbol: ts.symbol, added: added))
            }
        }
    }

    private func makeRow(symbol: String, added: Bool) -> NSView {
        let title = "\(added ? "✓ " : "+ ")\(SymbolFormat.displayCode(for: symbol))"
        let button = NSButton(title: title, target: self, action: #selector(rowClicked(_:)))
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.contentTintColor = added ? .systemGreen : .labelColor
        button.identifier = NSUserInterfaceItemIdentifier(symbol)
        return button
    }

    @objc private func rowClicked(_ sender: NSButton) {
        guard let symbol = sender.identifier?.rawValue else { return }
        manager.toggleCryptoSelection(symbol)
        onChange()
        reload()
    }
}
