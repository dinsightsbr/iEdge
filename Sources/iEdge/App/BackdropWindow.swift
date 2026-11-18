import AppKit

/// `--backdrop` (development only): a borderless, click-through window the size of the screen with a
/// soft wallpaper-like gradient. It sits at the sidebar's level and is ordered in before any panel,
/// so the panels draw over it and screenshots of the real app show nothing of the user's screen
/// (menu bar and Dock included).
@MainActor
final class BackdropWindow: NSWindow {
    /// Top-to-bottom gradient stops (sRGB, 0…1). Pure so the palette can be tested.
    static func gradient(dark: Bool) -> [(red: Double, green: Double, blue: Double)] {
        dark
            ? [(0.11, 0.13, 0.24), (0.20, 0.16, 0.33), (0.30, 0.18, 0.30)]
            : [(0.78, 0.86, 0.97), (0.87, 0.84, 0.96), (0.98, 0.89, 0.86)]
    }

    init(screen: NSScreen, dark: Bool) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = true
        hasShadow = false
        isReleasedWhenClosed = false
        backgroundColor = .black

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        let layer = CAGradientLayer()
        layer.colors = Self.gradient(dark: dark).map {
            CGColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1)
        }
        // Layer coordinates start at the bottom: run the stops from the top-left corner down.
        layer.startPoint = CGPoint(x: 0.2, y: 1)
        layer.endPoint = CGPoint(x: 0.8, y: 0)
        view.layer = layer
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
