import SwiftUI

extension Color {
    /// Claude's brand blue — pixel-sampled from the usage progress bars on
    /// claude.com (#4177D0, RGB 65/119/208). Defined in one place so any
    /// future tweak to match a brand update is a single-file change.
    static let claudeBlue = Color(red: 0.255, green: 0.467, blue: 0.816)

    /// Soft warm gray for progress bar tracks. Picked to read well in both
    /// light and dark mode without going gloomy in dark.
    static let claudeTrack = Color.primary.opacity(0.10)
}
