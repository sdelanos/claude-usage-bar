import AppKit

/// Loads the Claude tray-icon template (PNG bundled in Contents/Resources).
/// `.isTemplate = true` is the bit that makes macOS recolor the icon to match
/// the menubar — black in light mode, white in dark mode — so we never have
/// to do it ourselves.
enum MenuBarIcon {

    /// Returns a fresh NSImage every call. `NSImage` is mutable (size), so each
    /// caller gets its own instance to size independently.
    static func load(size: CGFloat) -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        image.size = NSSize(width: size, height: size)
        return image
    }
}
