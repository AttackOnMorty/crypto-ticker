//
//  NothingControls.swift
//  CryptoTicker
//
//  The small AppKit pieces the panel is built from: a tracked label, a hairline, and a
//  mechanical toggle. Kept apart from the panel so each one is a single readable thing.
//

import AppKit

/// A non-editable label that keeps its tracking and colour when the text changes.
/// `NSTextField(labelWithString:)` would drop the kerning on every assignment, and the
/// ALL-CAPS labels are unreadable without it.
final class NothingLabel: NSTextField {
    private let tracking: CGFloat

    /// - Parameter tracking: letter spacing in em, matching the design token.
    init(font: NSFont, color: NSColor, tracking: CGFloat = 0, alignment: NSTextAlignment = .left) {
        self.tracking = tracking
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
        self.font = font
        textColor = color
        self.alignment = alignment
        translatesAutoresizingMaskIntoConstraints = false
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var text: String = "" {
        didSet { applyAttributes() }
    }

    override var textColor: NSColor? {
        didSet { if !text.isEmpty { applyAttributes() } }
    }

    private func applyAttributes() {
        guard let font, let textColor else { return }
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        if tracking != 0 {
            attributes[.kern] = tracking * font.pointSize
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        attributes[.paragraphStyle] = paragraph
        attributedStringValue = NSAttributedString(string: text, attributes: attributes)
    }
}

/// A one-pixel rule. Used only where rows are structurally identical and spacing alone
/// would leave them ambiguous.
final class HairlineView: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: NothingTheme.Metric.hairline).isActive = true
        updateColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() { updateColor() }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    private func updateColor() {
        // `cgColor` freezes the appearance current at resolution time, so pin it to this
        // view's own before reading a dynamic colour.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NothingTheme.Palette.border.cgColor
        }
    }
}

/// A current UTC-day sparkline. The line is deliberately neutral: direction is already
/// encoded by the adjacent percentage, so repeating red/green here would create a second
/// accent event. No fill, axes, grid or enclosing card compete with the data itself.
final class DayChartView: NSView {
    private let startLabel: NothingLabel
    private let endLabel: NothingLabel
    private let plot: DaySparklinePlot

    var state: PanelSnapshot.DayChart = .loading {
        didSet { plot.state = state }
    }

    init() {
        let font = NothingTheme.data(size: NothingTheme.TypeSize.label)
        startLabel = NothingLabel(
            font: font,
            color: NothingTheme.Palette.textDisabled,
            tracking: NothingTheme.labelTracking
        )
        endLabel = NothingLabel(
            font: font,
            color: NothingTheme.Palette.textDisabled,
            tracking: NothingTheme.labelTracking,
            alignment: .right
        )
        plot = DaySparklinePlot()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        startLabel.text = "00 UTC"
        endLabel.text = "NOW"
        for view in [plot, startLabel, endLabel] { addSubview(view) }
        NSLayoutConstraint.activate([
            plot.leadingAnchor.constraint(equalTo: leadingAnchor),
            plot.trailingAnchor.constraint(equalTo: trailingAnchor),
            plot.topAnchor.constraint(equalTo: topAnchor),
            plot.heightAnchor.constraint(equalToConstant: NothingTheme.Metric.chartHeight),

            startLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            startLabel.topAnchor.constraint(equalTo: plot.bottomAnchor, constant: NothingTheme.Metric.xs),
            startLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            endLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            endLabel.firstBaselineAnchor.constraint(equalTo: startLabel.firstBaselineAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class DaySparklinePlot: NSView {
    var state: PanelSnapshot.DayChart = .loading {
        didSet { needsDisplay = true }
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard case .points(let points) = state else {
            drawState(ifUnavailable: state)
            return
        }
        guard points.count > 1,
              let low = points.min(),
              let high = points.max() else {
            drawState("[LOADING]")
            return
        }

        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineJoinStyle = .round
        path.lineCapStyle = .round

        let plotBounds = bounds.insetBy(dx: 0.75, dy: 2)
        let range = high - low
        for (index, value) in points.enumerated() {
            let x = plotBounds.minX
                + CGFloat(index) / CGFloat(points.count - 1) * plotBounds.width
            let normalizedY = range == 0 ? 0.5 : (value - low) / range
            let y = plotBounds.maxY - CGFloat(normalizedY) * plotBounds.height
            let point = NSPoint(x: x, y: y)
            index == 0 ? path.move(to: point) : path.line(to: point)
        }

        effectiveAppearance.performAsCurrentDrawingAppearance {
            NothingTheme.Palette.textPrimary.setStroke()
            path.stroke()
        }
    }

    private func drawState(ifUnavailable state: PanelSnapshot.DayChart) {
        if case .unavailable = state {
            drawState("[NO DATA]")
        } else {
            drawState("[LOADING]")
        }
    }

    private func drawState(_ text: String) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let font = NothingTheme.data(size: NothingTheme.TypeSize.label)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NothingTheme.Palette.textDisabled,
                .kern: NothingTheme.labelTracking * font.pointSize,
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(
                at: NSPoint(x: bounds.minX, y: bounds.midY - size.height / 2),
                withAttributes: attributes
            )
        }
    }
}

/// A label that is also a button. There is no bordered button anywhere in the panel — a
/// control announces itself by brightening under the cursor, which is all the affordance
/// a five-element panel needs.
final class NothingTextButton: NSControl {
    private let label: NothingLabel
    private let restingColor: NSColor
    private let activeColor: NSColor

    init(text: String, font: NSFont, color: NSColor, activeColor: NSColor, tracking: CGFloat = 0) {
        label = NothingLabel(font: font, color: color, tracking: tracking)
        restingColor = color
        self.activeColor = activeColor
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        // One stable tracking area follows the visible bounds automatically. Rebuilding
        // every tracking area from `updateTrackingAreas()` creates an AppKit cursor-update
        // loop and can consume an entire CPU core while the panel is open.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

    override func mouseEntered(with event: NSEvent) { label.textColor = activeColor }
    override func mouseExited(with event: NSEvent) { label.textColor = restingColor }
}
