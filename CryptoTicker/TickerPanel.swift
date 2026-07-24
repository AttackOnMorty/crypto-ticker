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
        let isSelected: Bool
    }

    /// The one coin in the display layer. Which coin that is, is the user's choice.
    let hero: Coin
    /// The remaining coins, in the supporting layer.
    let others: [Coin]
    let updated: String
}

extension PanelText.Status {
    var color: NSColor {
        switch self {
        case .live: return NothingTheme.Palette.success
        case .sync: return NothingTheme.Palette.warning
        case .lost: return NothingTheme.Palette.accent
        case .idle: return NothingTheme.Palette.textDisabled
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
    func panelView(_ view: TickerPanelView, didFocus symbol: String)
    func panelView(_ view: TickerPanelView, didToggle symbol: String)
    func panelViewDidRequestQuit(_ view: TickerPanelView)
}

// MARK: - Stat row

/// A coin in the supporting layer. Clicking it promotes it to the hero slot — the row
/// brightens under the cursor to say so, which is the only affordance the design allows.
final class StatRowView: NSControl {
    private let codeLabel: NothingLabel
    private let priceLabel: NothingLabel
    private let changeLabel: NothingLabel
    private var isHovered = false

    private(set) var symbol = ""

    override init(frame frameRect: NSRect) {
        codeLabel = NothingLabel(
            font: NothingTheme.data(size: NothingTheme.TypeSize.label),
            color: NothingTheme.Palette.textSecondary,
            tracking: NothingTheme.labelTracking
        )
        priceLabel = NothingLabel(
            font: NothingTheme.data(size: NothingTheme.TypeSize.value),
            color: NothingTheme.Palette.textPrimary,
            alignment: .right
        )
        changeLabel = NothingLabel(
            font: NothingTheme.data(size: NothingTheme.TypeSize.label),
            color: NothingTheme.Palette.textDisabled,
            alignment: .right
        )
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        for view in [codeLabel, priceLabel, changeLabel] { addSubview(view) }
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: priceLabel.topAnchor, constant: -NothingTheme.Metric.sm),
            priceLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            changeLabel.topAnchor.constraint(equalTo: priceLabel.bottomAnchor, constant: 2),
            changeLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomAnchor.constraint(equalTo: changeLabel.bottomAnchor, constant: NothingTheme.Metric.sm),
            codeLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            codeLabel.firstBaselineAnchor.constraint(equalTo: priceLabel.firstBaselineAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(with coin: PanelSnapshot.Coin) {
        symbol = coin.symbol
        codeLabel.text = coin.pair
        priceLabel.text = coin.price
        changeLabel.text = coin.change.text
        changeLabel.textColor = coin.change.direction.color
        applyHoverColors()
    }

    private func applyHoverColors() {
        codeLabel.textColor = isHovered ? NothingTheme.Palette.textPrimary : NothingTheme.Palette.textSecondary
        priceLabel.textColor = isHovered ? NothingTheme.Palette.textDisplay : NothingTheme.Palette.textPrimary
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyHoverColors()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyHoverColors()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Status dot

/// The single dot that reports the hero's connection. The one moment of colour in the
/// header, and the only thing on the panel allowed to turn red on its own.
final class StatusDot: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        let size = NothingTheme.Metric.statusDotSize
        layer?.cornerRadius = size / 2
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var color: NSColor = NothingTheme.Palette.textDisabled {
        didSet { needsDisplay = true }
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        // `cgColor` snapshots whatever appearance is current, so resolve it against this
        // view's own — otherwise a dynamic colour freezes at the mode it was first drawn in.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = color.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        needsDisplay = true
    }
}

// MARK: - Panel content

final class TickerPanelView: NSView {
    private typealias Metric = NothingTheme.Metric

    weak var delegate: TickerPanelViewDelegate?

    private let headerPair: NothingLabel
    private let headerStatus: NothingLabel
    private let statusDot = StatusDot()
    private let heroPrice: NothingLabel
    private let heroChange: NothingLabel
    private let updatedLabel: NothingLabel
    private var statRows: [StatRowView] = []
    private var switches: [String: MechanicalSwitch] = [:]

    /// - Parameter symbols: every supported coin, in a fixed order. The switch row and the
    ///   stat rows are sized from this once — the panel is never rebuilt, only refreshed.
    init(symbols: [String]) {
        let labelFont = NothingTheme.data(size: NothingTheme.TypeSize.label)
        headerPair = NothingLabel(font: labelFont, color: NothingTheme.Palette.textSecondary, tracking: NothingTheme.labelTracking)
        headerStatus = NothingLabel(font: labelFont, color: NothingTheme.Palette.textDisabled, tracking: NothingTheme.labelTracking, alignment: .right)
        heroPrice = NothingLabel(
            font: NothingTheme.display(size: NothingTheme.TypeSize.hero),
            color: NothingTheme.Palette.textDisplay
        )
        heroChange = NothingLabel(
            font: NothingTheme.data(size: NothingTheme.TypeSize.value),
            color: NothingTheme.Palette.textDisabled
        )
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

        // Tertiary: what this is, and whether the feed is alive.
        let header = makeRow(leading: headerPair, trailing: [statusDot, headerStatus])
        addFullWidth(header, to: stack)
        stack.setCustomSpacing(Metric.lg, after: header)

        // Primary: the one number the app exists to show.
        addFullWidth(heroPrice, to: stack)
        stack.setCustomSpacing(Metric.xs, after: heroPrice)
        addFullWidth(heroChange, to: stack)
        stack.setCustomSpacing(Metric.xl, after: heroChange)

        // The only rule on the panel: the rows below it are structurally identical, which
        // is the one case where spacing alone leaves the grouping ambiguous.
        let hairline = HairlineView()
        addFullWidth(hairline, to: stack)
        stack.setCustomSpacing(Metric.sm, after: hairline)

        statRows = (1..<max(symbols.count, 1)).map { _ in
            let row = StatRowView(frame: .zero)
            row.target = self
            row.action = #selector(statRowClicked(_:))
            addFullWidth(row, to: stack)
            return row
        }
        if let last = statRows.last {
            stack.setCustomSpacing(Metric.xl, after: last)
        } else {
            stack.setCustomSpacing(Metric.xl, after: hairline)
        }

        let menuBarLabel = NothingLabel(
            font: NothingTheme.data(size: NothingTheme.TypeSize.label),
            color: NothingTheme.Palette.textDisabled,
            tracking: NothingTheme.labelTracking
        )
        menuBarLabel.text = "MENU BAR"
        addFullWidth(menuBarLabel, to: stack)
        stack.setCustomSpacing(Metric.sm, after: menuBarLabel)

        // Laid out by hand rather than with a horizontal `NSStackView`: the stack fills the
        // panel width and pushes the switches to opposite edges, and they read as one
        // control cluster only while they stay together.
        let switchRow = NSView()
        switchRow.translatesAutoresizingMaskIntoConstraints = false
        var leadingEdge = switchRow.leadingAnchor
        for (index, symbol) in symbols.enumerated() {
            let group = makeSwitchGroup(for: symbol)
            switchRow.addSubview(group)
            NSLayoutConstraint.activate([
                group.leadingAnchor.constraint(equalTo: leadingEdge, constant: index == 0 ? 0 : Metric.lg),
                group.topAnchor.constraint(equalTo: switchRow.topAnchor),
                group.bottomAnchor.constraint(equalTo: switchRow.bottomAnchor),
            ])
            leadingEdge = group.trailingAnchor
        }
        addFullWidth(switchRow, to: stack)
        stack.setCustomSpacing(Metric.xl, after: switchRow)

        let quit = NothingTextButton(
            text: "QUIT",
            font: NothingTheme.data(size: NothingTheme.TypeSize.label),
            color: NothingTheme.Palette.textSecondary,
            activeColor: NothingTheme.Palette.accent,
            tracking: NothingTheme.labelTracking
        )
        quit.target = self
        quit.action = #selector(quitClicked)
        addFullWidth(makeRow(leading: updatedLabel, trailing: [quit]), to: stack)
    }

    private func makeSwitchGroup(for symbol: String) -> NSView {
        let code = NothingLabel(
            font: NothingTheme.data(size: NothingTheme.TypeSize.label),
            color: NothingTheme.Palette.textSecondary,
            tracking: NothingTheme.labelTracking
        )
        code.text = SymbolCatalog.displayCode(for: symbol)

        let toggle = MechanicalSwitch()
        toggle.identifier = NSUserInterfaceItemIdentifier(symbol)
        toggle.target = self
        toggle.action = #selector(switchToggled(_:))
        switches[symbol] = toggle

        let group = NSStackView(views: [code, toggle])
        group.orientation = .horizontal
        group.alignment = .centerY
        group.spacing = NothingTheme.Metric.sm
        return group
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
        headerPair.text = snapshot.hero.pair
        headerStatus.text = snapshot.hero.status.rawValue
        headerStatus.textColor = snapshot.hero.status.color
        statusDot.color = snapshot.hero.status.color
        statusDot.needsDisplay = true

        heroPrice.text = snapshot.hero.price
        heroChange.text = snapshot.hero.change.text
        heroChange.textColor = snapshot.hero.change.direction.color

        for (row, coin) in zip(statRows, snapshot.others) {
            row.update(with: coin)
        }

        for coin in [snapshot.hero] + snapshot.others {
            switches[coin.symbol]?.isOn = coin.isSelected
        }

        updatedLabel.text = snapshot.updated
    }

    // MARK: Actions

    @objc private func statRowClicked(_ sender: StatRowView) {
        delegate?.panelView(self, didFocus: sender.symbol)
    }

    @objc private func switchToggled(_ sender: MechanicalSwitch) {
        guard let symbol = sender.identifier?.rawValue else { return }
        delegate?.panelView(self, didToggle: symbol)
    }

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
        hidesOnDeactivate = true
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
    /// The status item's own window. Clicks in it are left alone so the button's own
    /// action decides — dismissing here would close the panel and let the click reopen it.
    private weak var anchorWindow: NSWindow?

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
        anchorWindow = button.window
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
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            Task { @MainActor in self?.hide() }
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
            if event.window !== self.panel && event.window !== self.anchorWindow {
                self.hide()
            }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}
