import AppKit
import SwiftUI

/// Borderless glass panel, like the Control Center modules: rounded corners, Liquid Glass on
/// macOS 26 (vibrancy before that). Used by the sidebar, the clipboard flyout, the capture toast
/// and Settings, each with its own margins, radius, level and key behaviour.
///
/// The glass draws its own soft shadow, which spills past its rounded shape (and the sidebar's
/// magnified tiles spill past the capsule). The window is therefore larger than the glass by
/// `margins`, so both fade out inside it instead of being cut by the window's square edge. The
/// window shadow stays off: it would follow the square window, not the glass.
class GlassPanel: NSPanel {
    struct Configuration {
        var radius: CGFloat
        var margins: NSEdgeInsets
        var level: NSWindow.Level = .popUpMenu
        var collectionBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        /// Settings needs key status for text fields; the sidebar must never take it from the
        /// frontmost app (paste and captures act on that app).
        var canBecomeKey = true

        /// Settings under the menu-bar icon (the iSessions StatusPanel).
        static let settings = Configuration(
            radius: Theme.panelRadius,
            margins: NSEdgeInsets(top: 0, left: 22, bottom: 30, right: 22)
        )
    }

    let configuration: Configuration
    var margins: NSEdgeInsets { configuration.margins }

    /// Esc, or a click on the transparent margin around the glass.
    var onDismiss: (() -> Void)?

    init(content: NSView, configuration: Configuration) {
        self.configuration = configuration
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = configuration.level
        collectionBehavior = configuration.collectionBehavior
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none

        let container = MarginView(content: content, radius: configuration.radius, margins: configuration.margins)
        container.onOutsideClick = { [weak self] in self?.onDismiss?() }
        contentView = container
        // The glass and SwiftUI give this window an Auto Layout engine. Left to the autoresizing
        // translation, the constraints AppKit derives between its frame view and the content view
        // capture a stale offset on every resize and the engine then stretches the content view by
        // that delta again; pinning the content view explicitly keeps it the window's size.
        if let frameView = container.superview {
            container.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: frameView.leadingAnchor),
                container.trailingAnchor.constraint(equalTo: frameView.trailingAnchor),
                container.topAnchor.constraint(equalTo: frameView.topAnchor),
                container.bottomAnchor.constraint(equalTo: frameView.bottomAnchor),
            ])
        }
    }

    /// Window frame for a glass rectangle (both in screen coordinates).
    func frame(forGlass glass: NSRect) -> NSRect {
        NSRect(
            x: glass.minX - margins.left,
            y: glass.minY - margins.bottom,
            width: glass.width + margins.left + margins.right,
            height: glass.height + margins.top + margins.bottom
        )
    }

    /// Glass rectangle of the current window frame, in screen coordinates.
    var glassFrame: NSRect {
        NSRect(
            x: frame.minX + margins.left,
            y: frame.minY + margins.bottom,
            width: frame.width - margins.left - margins.right,
            height: frame.height - margins.top - margins.bottom
        )
    }

    func setGlassFrame(_ glass: NSRect, display: Bool) {
        setFrame(frame(forGlass: glass), display: display)
    }

    /// The glass rectangle as `x y w h` in the top-left based coordinates `screencapture -R` uses
    /// (for `--frame-file`).
    var glassFrameForCapture: String {
        Self.captureString(for: glassFrame)
    }

    static func captureString(for rect: NSRect) -> String {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? rect.maxY
        return String(format: "%.0f %.0f %.0f %.0f", rect.minX, primaryHeight - rect.maxY, rect.width, rect.height)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        // Lay the content out now rather than in the deferred pass, so SwiftUI sees its final
        // size immediately and the height it reports back matches the window.
        contentView?.superview?.layoutSubtreeIfNeeded()
    }

    override var canBecomeKey: Bool { configuration.canBecomeKey }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}

/// Hosting view that takes the first click even though its (non-activating) window is not key,
/// so a tile reacts on the very first click without activating iEdge.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Holds the glass inset by fixed margins; a click on the margin counts as clicking away.
///
/// The content is a sibling drawn over the glass rather than the glass's `contentView`, and
/// everything is pinned with explicit constraints: `NSGlassEffectView` lays its content view out
/// with Auto Layout, and on macOS 26 mixing that with autoresizing applied each window resize
/// twice to the content (content = glass + delta, accumulating with every resize).
///
/// The content is clipped to the glass shape. Content that must overflow the glass (magnified
/// tiles) can be added by the owner as a separate subview of the panel's content view.
private final class MarginView: NSView {
    private let glass: NSView
    private let clip: NSView
    var onOutsideClick: (() -> Void)?

    init(content: NSView, radius: CGFloat, margins: NSEdgeInsets) {
        self.glass = Self.glass(radius: radius)
        self.clip = NSView(frame: .zero)
        super.init(frame: NSRect(x: 0, y: 0, width: 380 + margins.left + margins.right, height: 320 + margins.top + margins.bottom))
        clip.wantsLayer = true
        clip.layer?.cornerRadius = radius
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        clip.addSubview(content)
        addSubview(glass)
        addSubview(clip)

        for view in [glass, clip, content] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        var constraints: [NSLayoutConstraint] = []
        for view in [glass, clip] {
            constraints += [
                view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margins.left),
                view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margins.right),
                view.topAnchor.constraint(equalTo: topAnchor, constant: margins.top),
                view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -margins.bottom),
            ]
        }
        constraints += [
            content.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            content.topAnchor.constraint(equalTo: clip.topAnchor),
            content.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
        ]
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if glass.frame.contains(point) {
            super.mouseDown(with: event)
        } else {
            onOutsideClick?()
        }
    }

    private static func glass(radius: CGFloat) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: .zero)
            glass.cornerRadius = radius
            glass.style = .regular
            return glass
        }

        let effect = NSVisualEffectView(frame: .zero)
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = radius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        return effect
    }
}
