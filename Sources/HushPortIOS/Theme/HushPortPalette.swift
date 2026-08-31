#if os(iOS)
import SwiftUI

enum HushPortPalette {
    static let brand = Color(red: 0.42, green: 0.29, blue: 1.00)
    static let brandBright = Color(red: 0.25, green: 0.47, blue: 1.00)
    static let cyan = Color(red: 0.20, green: 0.76, blue: 1.00)
    static let success = Color(red: 0.18, green: 0.78, blue: 0.49)
    static let background = Color(red: 0.018, green: 0.025, blue: 0.055)
    static let panel = Color(red: 0.055, green: 0.065, blue: 0.095)
    static let panelRaised = Color(red: 0.075, green: 0.085, blue: 0.12)
    static let border = Color.white.opacity(0.09)
}
#endif
