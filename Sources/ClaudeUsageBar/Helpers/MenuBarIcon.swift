import AppKit

/// Loads the Claude tray-icon template (PNG bundled in `Contents/Resources`).
///
/// `.isTemplate = true` is the bit that makes macOS recolor the icon to
/// match the menubar — black in light mode, white in dark mode — so we
/// never have to do it ourselves.
///
/// Cached per size on the main actor: callers pass a size, we return a
/// shared `NSImage` from a small dictionary. `NSImage` is mutable in
/// principle, but we never write to it after init, so a single instance per
/// size is safe.
@MainActor
enum MenuBarIcon {
    private static var cache: [CGFloat: NSImage] = [:]

    static func image(size: CGFloat) -> NSImage? {
        if let cached = cache[size] { return cached }
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        image.size = NSSize(width: size, height: size)
        cache[size] = image
        return image
    }
}
