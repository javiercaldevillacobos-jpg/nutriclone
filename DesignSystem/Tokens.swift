import SwiftUI
import UIKit

/// Tokens de diseño. Los componentes usan solo estos valores, nunca colores o medidas sueltos.
/// Paleta provisional propia; /replica-design y /replica-brand la sustituirán.
enum DS {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 20
    }

    enum Size {
        static let ringLarge: CGFloat = 168
        static let ringMedium: CGFloat = 132
        static let ringStroke: CGFloat = 14
        static let barHeight: CGFloat = 8
        static let minTap: CGFloat = 44
        static let chartHeight: CGFloat = 220
    }
}

extension Color {
    static let brand = Color.dynamic(light: 0xE8_5D_2C, dark: 0xFF_85_57)
    static let brandSoft = Color.dynamic(light: 0xFD_EC_E4, dark: 0x3A_22_18)
    static let protein = Color.dynamic(light: 0xD9_3F_5B, dark: 0xF2_6D_85)
    static let carbs = Color.dynamic(light: 0xD8_9A_0E, dark: 0xF5_C0_45)
    static let fat = Color.dynamic(light: 0x3E_7C_D6, dark: 0x6F_A4_F0)
    static let water = Color.dynamic(light: 0x1E_9B_D7, dark: 0x5C_BE_EE)
    static let over = Color.dynamic(light: 0xC6_28_28, dark: 0xFF_6B_6B)
    static let ringTrack = Color(uiColor: .systemGray5)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let screen = Color(uiColor: .systemGroupedBackground)

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}
