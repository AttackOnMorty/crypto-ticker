//
//  NothingTheme.swift
//  Tickbyte
//
//  The design system's tokens — colour, type, metrics — in one place, so no hex literal
//  or point size appears in view code. Mirrors the Nothing token set: monochrome canvas,
//  colour only where it encodes data status, dark and light treated as equals.
//

import AppKit

enum NothingTheme {

    // MARK: - Colour

    /// Dark reads as an instrument panel in a dark room (OLED black, data glowing);
    /// light reads as a printed technical manual (off-white paper, black ink). Every
    /// text/surface token is dynamic so a single view works in both.
    enum Palette {
        static let background = dynamic(dark: 0x000000, light: 0xF5F5F5)
        static let border = dynamic(dark: 0x222222, light: 0xE8E8E8)
        static let borderVisible = dynamic(dark: 0x333333, light: 0xCCCCCC)
        static let textDisabled = dynamic(dark: 0x666666, light: 0x999999)
        static let textSecondary = dynamic(dark: 0x999999, light: 0x666666)
        static let textPrimary = dynamic(dark: 0xE8E8E8, light: 0x1A1A1A)
        static let textDisplay = dynamic(dark: 0xFFFFFF, light: 0x000000)

        /// Status colours are identical in both modes — they encode data, not chrome.
        /// `accent` is the interrupt: nothing else on screen may use it.
        static let accent = NSColor(rgb: 0xD71921)
        // The original green remains legible on OLED black; light mode needs a darker
        // value to keep 16pt market movement above normal-text contrast requirements.
        static let success = dynamic(dark: 0x4A9E5C, light: 0x2E7D42)
        static let warning = NSColor(rgb: 0xD4A843)

        private static func dynamic(dark: Int, light: Int) -> NSColor {
            NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(rgb: isDark ? dark : light)
            }
        }
    }

    // MARK: - Type

    /// Bundled families. Doto is the dot-matrix display face (hero numbers only),
    /// Space Mono carries all data and ALL-CAPS labels, Space Grotesk the little prose
    /// there is. Both variable faces resolve through a family + weight descriptor
    /// because their named instances ("SpaceGrotesk-Light_Medium") are not addressable
    /// by PostScript name.
    private enum Family {
        static let display = "Doto"
        static let body = "Space Grotesk"
        static let data = "Space Mono"
    }

    /// Exactly three token sizes on the panel — display-lg, body, label — and the
    /// platform-owned menu-bar size.
    /// Anything that wants a fourth is a spacing problem, not a type problem.
    enum TypeSize {
        static let hero: CGFloat = 48
        static let value: CGFloat = 16
        static let label: CGFloat = 11
        static let menuBar: CGFloat = 12
    }

    /// ALL-CAPS labels need the wide 0.08em tracking that makes them read as instrument
    /// legends rather than shouting.
    static let labelTracking: CGFloat = 0.08

    static func display(size: CGFloat) -> NSFont {
        resolve(Family.display, size: size, weight: .regular)
            ?? .monospacedDigitSystemFont(ofSize: size, weight: .medium)
    }

    static func data(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        resolve(Family.data, size: size, weight: weight)
            ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func body(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        resolve(Family.body, size: size, weight: weight)
            ?? .systemFont(ofSize: size, weight: weight)
    }

    private static func resolve(_ family: String, size: CGFloat, weight: NSFont.Weight) -> NSFont? {
        _ = registration
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [NSFontDescriptor.TraitKey.weight: weight],
        ])
        // A missing family still yields a descriptor, so confirm the match rather than
        // silently rendering the system fallback in place of the design's face.
        guard let font = NSFont(descriptor: descriptor, size: size), font.familyName == family else { return nil }
        return font
    }

    /// Registers the bundled faces into this process only — the app never installs
    /// fonts system-wide. Runs once, lazily, on the first font lookup.
    private static let registration: Void = {
        // Both lookups: Xcode flattens bundled resources, but a folder reference would
        // keep the Fonts directory — a missing face silently downgrades the whole panel
        // to system type, so it is worth checking both places.
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        for url in Set(urls) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    // MARK: - Metrics

    /// Spacing is the 8px scale. The gaps carry the grouping — there is no divider on
    /// the panel that a gap could have done instead.
    enum Metric {
        static let panelWidth: CGFloat = 300
        static let padding: CGFloat = 24
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let sectionGap: CGFloat = 48
        static let cornerRadius: CGFloat = 10
        static let hairline: CGFloat = 1
        static let chartHeight: CGFloat = 48
        /// Gap between the status-bar button and the top of the panel.
        static let panelOffset: CGFloat = 6
        static let buttonTarget: CGFloat = 44
        /// Transitions are percussive — a short ease-out, never a spring.
        static let transition: TimeInterval = 0.15
    }
}

extension NSColor {
    convenience init(rgb: Int) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
