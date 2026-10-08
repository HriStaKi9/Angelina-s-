import SwiftUI
import UIKit

/// Design tokens for the whole app. Every color adapts to light and dark mode,
/// so views never reach for raw `Color.white` / `Color.black`.
enum Theme {
    enum Palette {
        /// Warm cream page background.
        static let background = Color.dynamic(light: 0xFBF6F2, dark: 0x141016)
        /// Raised surfaces: cards, sheets, list rows.
        static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x211A24)
        /// Subtle fill for chips, inputs and tracks.
        static let surfaceMuted = Color.dynamic(light: 0xF3EAE6, dark: 0x2C2330)
        static let ink = Color.dynamic(light: 0x2A2024, dark: 0xF4ECEF)
        static let inkSecondary = Color.dynamic(light: 0x7A6A70, dark: 0xB3A3AA)
        static let hairline = Color.dynamic(light: 0xEBDFDA, dark: 0x382E3C)

        /// Brand berry — training, primary actions.
        static let berry = Color.dynamic(light: 0xD9576D, dark: 0xF47C8F)
        /// Sage — nutrition and "good" states.
        static let sage = Color.dynamic(light: 0x5E9478, dark: 0x86C2A2)
        /// Apricot — energy, calories, cardio.
        static let apricot = Color.dynamic(light: 0xE8925A, dark: 0xF4AD7E)
        /// Lavender — recovery, stretching.
        static let lavender = Color.dynamic(light: 0x8C7BC8, dark: 0xAE9FE6)

        static let onAccent = Color.white
    }

    enum Gradients {
        /// Deepens in dark mode (rather than lightening) so white text keeps its contrast.
        static let hero = LinearGradient(
            colors: [Color.dynamic(light: 0xD9576D, dark: 0xC94A61), Color.dynamic(light: 0xE8925A, dark: 0xD97B45)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let calm = LinearGradient(
            colors: [Palette.sage, Palette.lavender],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    enum Radius {
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }
}

extension Font {
    static let displayTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let sectionTitle = Font.system(.title3, design: .rounded).weight(.semibold)
    static let cardTitle = Font.system(.headline, design: .rounded)
    static let metric = Font.system(.title, design: .rounded).weight(.bold).monospacedDigit()
}

extension Color {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
