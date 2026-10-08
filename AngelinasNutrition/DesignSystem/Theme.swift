import SwiftUI
import UIKit

/// The two looks of the app: Rose (the original) and Steel (cooler slate and blue).
enum ThemeVariant: String, Codable, CaseIterable, Identifiable {
    case rose, steel

    var id: String { rawValue }

    /// Read by every themed color at draw time; RootView rebuilds the view tree when it changes.
    nonisolated(unsafe) static var current: ThemeVariant = .rose
}

/// Design tokens for the whole app. Every color adapts to light and dark mode and to the theme,
/// so views never reach for raw `Color.white` / `Color.black`.
enum Theme {
    enum Palette {
        /// Page background: warm cream (Rose) / cool slate (Steel).
        static let background = Color.themed(rose: (0xFBF6F2, 0x141016), steel: (0xF2F4F7, 0x0D1117))
        /// Raised surfaces: cards, sheets, list rows.
        static let surface = Color.themed(rose: (0xFFFFFF, 0x211A24), steel: (0xFFFFFF, 0x171D25))
        /// Subtle fill for chips, inputs and tracks.
        static let surfaceMuted = Color.themed(rose: (0xF3EAE6, 0x2C2330), steel: (0xE5E9EE, 0x232B35))
        static let ink = Color.themed(rose: (0x2A2024, 0xF4ECEF), steel: (0x18212C, 0xE7ECF2))
        static let inkSecondary = Color.themed(rose: (0x7A6A70, 0xB3A3AA), steel: (0x5D6978, 0x98A6B5))
        static let hairline = Color.themed(rose: (0xEBDFDA, 0x382E3C), steel: (0xDAE0E7, 0x2B3440))

        /// Primary accent — training, primary actions: berry (Rose) / steel blue (Steel).
        static let berry = Color.themed(rose: (0xD9576D, 0xF47C8F), steel: (0x2E6BB0, 0x5D9DE3))
        /// Nutrition and "good" states: sage / teal.
        static let sage = Color.themed(rose: (0x5E9478, 0x86C2A2), steel: (0x23856F, 0x4FC2A6))
        /// Energy, calories, cardio: apricot / amber.
        static let apricot = Color.themed(rose: (0xE8925A, 0xF4AD7E), steel: (0xD7861F, 0xF2A745))
        /// Recovery, stretching: lavender / slate indigo.
        static let lavender = Color.themed(rose: (0x8C7BC8, 0xAE9FE6), steel: (0x5B63B8, 0x8E95E6))

        static let onAccent = Color.white
    }

    enum Gradients {
        /// Deepens in dark mode (rather than lightening) so white text keeps its contrast.
        static let hero = LinearGradient(
            colors: [Color.themed(rose: (0xD9576D, 0xC94A61), steel: (0x1F4F86, 0x1B4473)),
                     Color.themed(rose: (0xE8925A, 0xD97B45), steel: (0x23856F, 0x1E7060))],
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
    /// A color with light/dark values for each theme.
    static func themed(rose: (light: UInt32, dark: UInt32), steel: (light: UInt32, dark: UInt32)) -> Color {
        Color(UIColor { traits in
            let pair = ThemeVariant.current == .steel ? steel : rose
            return UIColor(hex: traits.userInterfaceStyle == .dark ? pair.dark : pair.light)
        })
    }

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
