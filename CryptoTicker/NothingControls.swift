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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { label.textColor = activeColor }
    override func mouseExited(with event: NSEvent) { label.textColor = restingColor }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// A physical switch: pill track, circular thumb and two definite stops. The visible
/// instrument sits inside a 44pt target. Motion is 150ms with no bounce — a click, not
/// a swoosh.
final class MechanicalSwitch: NSControl {
    private let track = CALayer()
    private let knob = CALayer()
    private var isHovered = false

    var isOn: Bool = false {
        didSet { layout(animated: true) }
    }

    init() {
        let target = NothingTheme.Metric.controlTarget
        super.init(frame: NSRect(x: 0, y: 0, width: NothingTheme.Metric.switchSize.width, height: target))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: NothingTheme.Metric.switchSize.width).isActive = true
        heightAnchor.constraint(equalToConstant: target).isActive = true

        track.borderWidth = NothingTheme.Metric.hairline
        track.cornerRadius = NothingTheme.Metric.switchSize.height / 2
        layer?.addSublayer(track)
        layer?.addSublayer(knob)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        layout(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        layout(animated: false)
    }

    private func layout(animated: Bool) {
        let trackSize = NothingTheme.Metric.switchSize
        let trackFrame = NSRect(
            x: (bounds.width - trackSize.width) / 2,
            y: (bounds.height - trackSize.height) / 2,
            width: trackSize.width,
            height: trackSize.height
        )
        let inset: CGFloat = 3
        let side = trackFrame.height - inset * 2
        let x = isOn ? trackFrame.maxX - inset - side : trackFrame.minX + inset

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated {
            CATransaction.setAnimationDuration(NothingTheme.Metric.transition)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1))
        }
        track.frame = trackFrame
        knob.frame = NSRect(
            x: x,
            y: trackFrame.minY + inset,
            width: side,
            height: side
        )
        knob.cornerRadius = side / 2
        // Dynamic colours must be resolved against this view's appearance before `cgColor`
        // snapshots them, or the switch stays in whichever mode drew it first.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            track.borderColor = (isOn || isHovered
                ? NothingTheme.Palette.textPrimary
                : NothingTheme.Palette.borderVisible).cgColor
            knob.backgroundColor = (isOn
                ? NothingTheme.Palette.textDisplay
                : NothingTheme.Palette.textDisabled).cgColor
        }
        CATransaction.commit()
    }

    // MARK: - Interaction

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        sendAction(action, to: target)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        layout(animated: false)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        layout(animated: false)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
