import AppKit
import QuartzCore
import SwiftUI

/// Glass capsule window of the sidebar: non-activating (the frontmost app stays active, so paste
/// and captures act on it), above normal windows, on every Space and over full-screen apps.
///
/// The panel draws no glass of its own (`drawsGlass: false`): the capsule, the tiles and the label
/// are all drawn by `SidebarOverlayView`, which covers the whole window, because the capsule
/// grows with the magnifier and the magnified tiles and the label spill past it. The window has
/// room for the largest stack from the start, so only the drawing changes while magnifying. One
/// panel per edge, since the room for that spill is on the side facing into the screen.
final class SidebarPanel: GlassPanel {
    /// Room past the capsule into the screen: magnified tiles (up to (2 − 1) × 56 − 10 pt) and the
    /// label next to them.
    static let inwardMargin: CGFloat = 270
    /// Room towards the screen edge, for the glass shadow.
    static let outwardMargin: CGFloat = 24
    /// Room above and below, for the capsule growing with the magnified stack (half of
    /// `Magnification.maxOverflow` on each side) and its shadow.
    static let verticalMargin: CGFloat = 130

    static let configuration = configuration(for: .left)

    static func configuration(for edge: ScreenEdge) -> GlassPanel.Configuration {
        GlassPanel.Configuration(
            radius: Theme.sidebarRadius,
            margins: NSEdgeInsets(
                top: verticalMargin,
                left: edge == .left ? outwardMargin : inwardMargin,
                bottom: verticalMargin,
                right: edge == .left ? inwardMargin : outwardMargin
            ),
            level: .statusBar,
            collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle],
            canBecomeKey: false,
            // SidebarView draws the capsule so it follows the magnifier with the tiles, in the
            // same frame and animation, without resizing the window.
            drawsGlass: false
        )
    }

    /// The clipboard flyout, a child window of the sidebar.
    static let flyoutConfiguration = GlassPanel.Configuration(
        radius: Theme.flyoutRadius,
        margins: NSEdgeInsets(top: 10, left: 22, bottom: 30, right: 22),
        level: .statusBar,
        collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle],
        canBecomeKey: false
    )

    let edge: ScreenEdge
    let overlay: SidebarOverlayView

    init(edge: ScreenEdge, overlay: SidebarOverlayView) {
        self.edge = edge
        self.overlay = overlay
        super.init(content: NSView(frame: .zero), configuration: Self.configuration(for: edge))
        guard let container = contentView else { return }
        container.wantsLayer = true
        container.addSubview(overlay)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: container.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    /// Top-left of the glass inside the window, in the overlay's top-down coordinates.
    var glassOriginInCanvas: CGPoint { CGPoint(x: margins.left, y: margins.top) }
}

/// Transparent view over the whole sidebar window that draws the tiles (SwiftUI) and takes the
/// clicks on them. Clicks elsewhere fall through to the margin (which closes the sidebar).
final class SidebarOverlayView: NSView {
    /// Whether a point (in this view's coordinates) is on the capsule or a tile.
    var isInteractive: (NSPoint) -> Bool = { _ in false }
    var onMouseDown: (NSEvent) -> Void = { _ in }

    init<Content: View>(rootView: Content) {
        super.init(frame: .zero)
        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in the superview's coordinates. The hosting view never gets the event: the
        // tiles are drawn, the click is handled here.
        let local = convert(point, from: superview)
        return isInteractive(local) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onMouseDown(event)
    }
}

// MARK: - Spring in and out

/// Layer animations of a whole glass window (glass, tiles and all), anchored on one point: the
/// sidebar jumps out of the edge, the flyout out of its tile. The layer's model values never
/// change, so AppKit's own layout of the view is not disturbed.
@MainActor enum SidebarAnimation {
    /// Spring of the jump (docs/SPEC.md §1.2: response ≈ 0.38, damping ≈ 0.72).
    static let response: Double = 0.38
    static let damping: Double = 0.72
    static let exitDuration: Double = 0.18

    /// SwiftUI spring with the same feel, for the tiles' cascade and the label.
    static var swiftUISpring: Animation { .spring(response: response, dampingFraction: damping) }

    /// Animates `view`'s layer from `offset` and `scale` around `pivot` (in the view's
    /// coordinates) to rest, with a spring, fading in.
    static func springIn(_ view: NSView, pivot: CGPoint, offset: CGVector, scale: CGFloat) {
        guard let layer = view.layer else { return }
        layer.removeAllAnimations()
        let from = transform(layer: layer, pivot: pivot, offset: offset, scale: scale)

        let spring = CASpringAnimation(perceptualDuration: response, bounce: 1 - damping)
        spring.keyPath = "transform"
        spring.fromValue = NSValue(caTransform3D: from)
        spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "iedge.spring")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.14
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "iedge.fade")
    }

    /// Moves `view`'s layer out towards `offset` with an ease-in, fading out, then calls `completion`.
    static func out(_ view: NSView, pivot: CGPoint, offset: CGVector, scale: CGFloat, completion: @escaping @MainActor () -> Void) {
        guard let layer = view.layer else {
            completion()
            return
        }
        layer.removeAllAnimations()
        let to = transform(layer: layer, pivot: pivot, offset: offset, scale: scale)

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated { completion() }
        }
        let move = CABasicAnimation(keyPath: "transform")
        move.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
        move.toValue = NSValue(caTransform3D: to)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        for animation in [move, fade] {
            animation.duration = exitDuration
            animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
        }
        layer.add(move, forKey: "iedge.spring")
        layer.add(fade, forKey: "iedge.fade")
        CATransaction.commit()
    }

    static func reset(_ view: NSView) {
        view.layer?.removeAllAnimations()
    }

    /// Scale around `pivot`, then translate by `offset`. The pivot is in the view's coordinates;
    /// the layer transforms around its anchor point, so the pivot is taken relative to it.
    private static func transform(layer: CALayer, pivot: CGPoint, offset: CGVector, scale: CGFloat) -> CATransform3D {
        let anchor = CGPoint(x: layer.anchorPoint.x * layer.bounds.width, y: layer.anchorPoint.y * layer.bounds.height)
        let px = pivot.x - anchor.x
        // A flipped layer geometry would invert y; AppKit view layers are not flipped here.
        let py = (layer.isGeometryFlipped ? layer.bounds.height - pivot.y : pivot.y) - anchor.y
        var t = CATransform3DMakeTranslation(-px, -py, 0)
        t = CATransform3DConcat(t, CATransform3DMakeScale(scale, scale, 1))
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(px + offset.dx, py + offset.dy, 0))
        return t
    }
}
