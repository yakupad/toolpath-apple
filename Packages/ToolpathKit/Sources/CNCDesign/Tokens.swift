import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
#endif

extension Color {
    /// A color with separate light and dark appearances (hex RGB, optional alpha).
    public init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        func make(_ hex: UInt32, _ alpha: Double) -> PlatformColor {
            PlatformColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha
            )
        }
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? make(dark, darkAlpha) : make(light, lightAlpha)
        })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? make(dark, darkAlpha) : make(light, lightAlpha)
        })
        #endif
    }

    public init(hex: UInt32, alpha: Double = 1) {
        self.init(light: hex, dark: hex, lightAlpha: alpha, darkAlpha: alpha)
    }
}

/// Toolpath design tokens. Every color has a light and a dark value.
/// Rule: red (`danger`) is reserved for danger — never used for motion or brand.
public enum TP {
    public enum Palette {
        /// Brand / primary action — safety orange.
        public static let accent = Color(light: 0xF26B1D, dark: 0xFF7A2E)
        /// Accent used as text on neutral surfaces (higher contrast).
        public static let accentText = Color(light: 0xC2410C, dark: 0xFF9A5C)
        /// Text placed on top of an accent fill.
        public static let onAccent = Color(hex: 0x1A0E06)

        public static let canvas = Color(light: 0xF2F2F7, dark: 0x15161A)
        public static let card = Color(light: 0xFFFFFF, dark: 0x1E1F25)
        public static let cardRaised = Color(light: 0xF4F4F5, dark: 0x24262C)
        public static let separator = Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.08)

        public static let textPrimary = Color(light: 0x1C1C1E, dark: 0xF2F2F4)
        public static let textSecondary = Color(light: 0x6B6B73, dark: 0xA1A1AA)
        public static let textTertiary = Color(light: 0x71717A, dark: 0x8E8E96)

        public static let danger = Color(light: 0xDC2626, dark: 0xF87171)
        public static let caution = Color(light: 0xA16207, dark: 0xFACC15)
        public static let success = Color(light: 0x16A34A, dark: 0x34D399)
        public static let info = Color(light: 0x2563EB, dark: 0x60A5FA)
    }

    /// Toolpath viewer colors. Darker in light mode for contrast on warm paper.
    public enum Viewer {
        public static let background = Color(light: 0xF4F2EE, dark: 0x121317)
        public static let gridMinor = Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.045)
        public static let gridMajor = Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.14, darkAlpha: 0.12)
        /// Lathe stock section behind the toolpath.
        public static let stock = Color(light: 0xB98B52, dark: 0xC9A06A, lightAlpha: 0.14, darkAlpha: 0.12)
        public static let rapid = Color(light: 0x2563EB, dark: 0x60A5FA)
        public static let cut = Color(light: 0x16A34A, dark: 0x34D399)
        public static let arcCW = Color(light: 0xD97706, dark: 0xFBBF24)
        public static let arcCCW = Color(light: 0x7C3AED, dark: 0xA78BFA)
        public static let danger = Palette.danger
        public static let caution = Palette.caution
        public static let toolHead = Color(light: 0x1C1C1E, dark: 0xFFFFFF)
        public static let envelope = Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.15, darkAlpha: 0.15)
    }

    public enum Metric {
        public static let gutter: CGFloat = 16
        public static let cardRadius: CGFloat = 20
        public static let rowRadius: CGFloat = 18
        public static let sectionSpacing: CGFloat = 24
        /// Primary touch target (workshop UX: bigger than the 44pt system minimum).
        public static let target: CGFloat = 52
        public static let targetWorkshop: CGFloat = 64
    }
}

extension Font {
    /// Monospaced, tabular numbers for machine values.
    public static func tpValue(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced).monospacedDigit()
    }

    public static let tpCode = Font.system(.caption, design: .monospaced)
}
