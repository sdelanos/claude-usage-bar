import SwiftUI

/// Centralized palette so any future brand-color tweak is a single-file
/// change.
extension Color {
    /// Claude's brand blue — pixel-sampled from the usage progress bars on
    /// claude.com (#4177D0, RGB 65/119/208).
    static let claudeBlue = Color(red: 0.255, green: 0.467, blue: 0.816)

    /// Soft track color for progress bars. Adapts between light and dark
    /// mode via `Color.primary`.
    static let claudeTrack = Color.primary.opacity(0.10)

    /// Overage banner background tint.
    static let claudeWarnBackground = Color.orange.opacity(0.10)
    /// Overage banner border.
    static let claudeWarnBorder = Color.orange.opacity(0.25)
}
