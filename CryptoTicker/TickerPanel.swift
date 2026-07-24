//
//  TickerPanel.swift
//  CryptoTicker
//
//  The dropdown. A borderless panel rather than an `NSMenu` or an `NSPopover`: both of
//  those impose a system material, a shadow and a fixed row shape, and the design calls
//  for a flat surface with one hairline border and no shadow at all.
//
//  Like the menu it replaces, the panel renders state handed to it and owns none — every
//  view is built once and refreshed in place.
//

import AppKit

/// Everything the panel needs to draw itself, already resolved by the caller.
struct PanelSnapshot {
    struct Coin {
        let symbol: String
        let pair: String
        let price: String
        let change: PanelText.Change
        let status: PanelText.Status
    }

    /// All supported coins are equal peers in one primary market board.
    let coins: [Coin]
    let updated: String
}

extension PanelText.Status {
    var color: NSColor {
        switch self {
        case .live: return NothingTheme.Palette.success
        case .sync: return NothingTheme.Palette.warning
        case .lost: return NothingTheme.Palette.accent
        }
    }
}

extension PanelText.Direction {
    var color: NSColor {
        switch self {
        case .up: return NothingTheme.Palette.success
        case .down: return NothingTheme.Palette.accent
        case .flat: return NothingTheme.Palette.textDisabled
        }
    }
}

@MainActor
protocol TickerPanelViewDelegate: AnyObject {
    func panelViewDidRequestQuit(_ view: TickerPanelView)
}

// MARK: - Coin section

/// One equal peer in the market board. Every coin receives the same type, spacing,
/// status treatment and menu-bar control; only the data changes.
final class CoinSectionView: NSView {
    private let pairLabel: NothingLabel
    private let statusLabel: NothingLabel
    private let priceLabel: NothingLabel
    private let changeLabel: NothingLabel

    init(symbol: String) {
        pairLabel = NothingLabel(
            font: NothingTheme.data(size: NothingTheme.TypeSize.label),
            color: NothingTheme.Palette.textSecondary,
            tracking: NothingTheme.labelTracking
        )
        statusLabel = NothingLabel(
            font: NothingTheme.data(size: NothingTheme.TypeSize.label),
            color: NothingTheme.Palette.textDisabled,
            tracking: NothingTheme.labelTracking,
            alignment: .right
        )
        priceLabel = NothingLabel(
            font: NothingTheme.display(size: NothingTheme.TypeSize.hero),
            color: NothingTheme.Palette.textDisplay
        )
        changeLabel = NothingLabel(
            font: NothingTheme.data(size: NothingTheme.TypeSize.value),
            color: NothingTheme.Palette.textDisabled
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        for view in [pairLabel, statusLabel, priceLabel, changeLabel] {
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            pairLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            pairLabel.topAnchor.constraint(equalTo: topAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusLabel.firstBaselineAnchor.constraint(equalTo: pairLabel.firstBaselineAnchor),

            priceLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            priceLabel.topAnchor.constraint(equalTo: pairLabel.bottomAnchor, constant: NothingTheme.Metric.md),
            priceLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            changeLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            changeLabel.topAnchor.constraint(equalTo: priceLabel.bottomAnchor, constant: NothingTheme.Metric.xs),
            changeLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(with coin: PanelSnapshot.Coin) {
        pairLabel.text = coin.pair
        statusLabel.text = "[\(coin.status.rawValue)]"
        statusLabel.textColor = coin.status.color
        priceLabel.text = coin.price
        changeLabel.text = coin.change.text
        changeLabel.textColor = coin.change.direction.color
    }
}

// MARK: - Panel content

final class TickerPanelView: NSView {
    private typealias Metric = NothingTheme.Metric

    weak var delegate: TickerPanelViewDelegate?

    private let updatedLabel: NothingLabel
    private var coinSections: [CoinSectionView] = []

    /// - Parameter symbols: every supported coin, in a fixed order. The switch row and the
    ///   stat rows are sized from this once — the panel is never rebuilt, only refreshed.
    init(symbols: [String]) {
        let labelFont = NothingTheme.data(size: NothingTheme.TypeSize.label)
        updatedLabel = NothingLabel(font: labelFont, color: NothingTheme.Palette.textDisabled, tracking: NothingTheme.labelTracking)

        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = NothingTheme.Metric.cornerRadius
        layer?.borderWidth = NothingTheme.Metric.hairline
        applyChrome()

        buildLayout(symbols: symbols)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() { applyChrome() }

    override func viewDidChangeEffectiveAppearance() {
        needsDisplay = true
    }

    private func applyChrome() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NothingTheme.Palette.background.cgColor
            layer?.borderColor = NothingTheme.Palette.borderVisible.cgColor
        }
    }

    // MARK: Layout

    private func buildLayout(symbols: [String]) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Metric.panelWidth),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metric.padding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metric.padding),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Metric.padding),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metric.padding),
        ])

        coinSections = symbols.enumerated().map { index, symbol in
            if index > 0 {
                let hairline = HairlineView()
                addFullWidth(hairline, to: stack)
                stack.setCustomSpacing(Metric.md, after: hairline)
            }

            let section = CoinSectionView(symbol: symbol)
            addFullWidth(section, to: stack)
            stack.setCustomSpacing(index == symbols.count - 1 ? Metric.xl : Metric.md, after: section)
            return section
        }

        let quit = NothingTextButton(
            text: "QUIT",
            font: NothingTheme.data(size: NothingTheme.TypeSize.label),
            color: NothingTheme.Palette.textSecondary,
            activeColor: NothingTheme.Palette.textPrimary,
            tracking: NothingTheme.labelTracking
        )
        quit.target = self
        quit.action = #selector(quitClicked)
        quit.heightAnchor.constraint(greaterThanOrEqualToConstant: Metric.buttonTarget).isActive = true
        addFullWidth(makeRow(leading: updatedLabel, trailing: [quit]), to: stack)
    }

    private func addFullWidth(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    /// A row with one thing on the left and a right-anchored group, the asymmetry the
    /// layout leans on. Height follows the tallest child.
    private func makeRow(leading: NSView, trailing: [NSView]) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(leading)
        NSLayoutConstraint.activate([
            leading.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            leading.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(greaterThanOrEqualTo: leading.heightAnchor),
        ])

        var previous = container.trailingAnchor
        for (index, view) in trailing.enumerated() {
            container.addSubview(view)
            NSLayoutConstraint.activate([
                view.trailingAnchor.constraint(equalTo: previous, constant: index == 0 ? 0 : -NothingTheme.Metric.sm),
                view.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                container.heightAnchor.constraint(greaterThanOrEqualTo: view.heightAnchor),
            ])
            previous = view.leadingAnchor
        }
        return container
    }

    // MARK: Refresh

    func update(with snapshot: PanelSnapshot) {
        for (section, coin) in zip(coinSections, snapshot.coins) {
            section.update(with: coin)
        }

        updatedLabel.text = snapshot.updated
    }

    // MARK: Actions

    @objc private func quitClicked() {
        delegate?.panelViewDidRequestQuit(self)
    }
}

// MARK: - Panel window

/// A borderless, shadowless window anchored under the status item. `NSPanel` (rather than
/// `NSWindow`) so it can take key input for Escape without activating the app.
final class TickerPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentView.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.contentView = contentView
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = false
        // Clicking the menu bar deactivates the app, so `hidesOnDeactivate` would close
        // the panel a moment before the status item's action reopened it — the panel could
        // then never be toggled shut. Dismissal is the monitors' job instead.
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - Presentation

/// Shows and hides the panel under the status item, and owns the dismissal rules an
/// `NSMenu` used to provide for free: click anywhere else, or press Escape.
@MainActor
final class TickerPanelController {
    let contentView: TickerPanelView

    /// Called as the panel opens and closes, so the caller can start and stop the live
    /// update traffic that only matters while it is on screen.
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?

    private let panel: TickerPanel
    private var monitors: [Any] = []
    /// The status item the panel hangs from. Clicks inside it are left alone so the
    /// button's own action decides — dismissing here would close the panel and let the
    /// same click reopen it.
    private weak var anchorButton: NSStatusBarButton?

    init(symbols: [String]) {
        contentView = TickerPanelView(symbols: symbols)
        panel = TickerPanel(contentView: contentView)
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(relativeTo button: NSStatusBarButton) {
        isVisible ? hide() : show(relativeTo: button)
    }

    func show(relativeTo button: NSStatusBarButton) {
        onOpen?()
        contentView.layoutSubtreeIfNeeded()
        let size = contentView.fittingSize
        panel.setContentSize(size)
        position(size: size, under: button)
        anchorButton = button
        panel.orderFrontRegardless()
        panel.makeKey()
        installMonitors()
    }

    func hide() {
        guard panel.isVisible else { return }
        removeMonitors()
        panel.orderOut(nil)
        onClose?()
    }

    private func position(size: NSSize, under button: NSStatusBarButton) {
        guard let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        var x = anchor.midX - size.width / 2
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            let margin = NothingTheme.Metric.sm
            x = min(max(x, visible.minX + margin), visible.maxX - size.width - margin)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: anchor.minY - NothingTheme.Metric.panelOffset - size.height))
    }

    private func installMonitors() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        // A click on our own status item is delivered to *both* monitors — macOS owns the
        // menu bar, so the event system treats the click as having gone to another
        // application while AppKit still routes it through this process. Either monitor
        // dismissing on it would close the panel a moment before the button's action
        // reopened it, and the panel could never be toggled shut. Both must let it past.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.clickIsOnAnchor() else { return }
                self.hide()
            }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown), handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                // 53 = Escape.
                if event.keyCode == 53 {
                    self.hide()
                    return nil
                }
                return event
            }
            if event.window !== self.panel && event.window !== self.anchorButton?.window {
                self.hide()
            }
            return event
        }) {
            monitors.append(local)
        }
    }

    /// Whether the pointer is over the status item. A global event carries no window to
    /// compare against, so the anchor has to be recognised geometrically there.
    private func clickIsOnAnchor() -> Bool {
        guard let button = anchorButton, let window = button.window else { return false }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(NSEvent.mouseLocation)
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}
