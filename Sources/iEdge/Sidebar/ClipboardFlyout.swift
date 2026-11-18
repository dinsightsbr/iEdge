import AppKit
import SwiftUI

/// The clipboard history beside the sidebar (docs/SPEC.md §1.3): another glass, a child window of
/// the sidebar, against the capsule's inner side and aligned with the clipboard tile. It springs
/// out of the tile (scale 0.85 → 1 anchored on it) and closes with the sidebar.
@MainActor final class ClipboardFlyout {
    let panel: GlassPanel
    /// Side of the sidebar it sits against; it opens into the screen.
    let edge: ScreenEdge

    init(store: ClipboardStore, edge: ScreenEdge, onPick: @escaping (ClipboardEntry) -> Void) {
        self.edge = edge
        let list = ClipboardListView(store: store, onPick: onPick)
            .frame(width: Theme.flyoutWidth)
        let hosting = FirstMouseHostingView(rootView: list)
        let height = ceil(hosting.fittingSize.height)
        hosting.sizingOptions = []
        panel = GlassPanel(content: hosting, configuration: SidebarPanel.flyoutConfiguration)
        panel.contentView?.wantsLayer = true
        contentHeight = max(height, 80)
    }

    private let contentHeight: CGFloat

    var glassFrame: CGRect { panel.glassFrame }

    /// Places the flyout next to `sidebarGlass`, centred on `tile` and kept inside `visibleFrame`,
    /// attaches it to `parent` and springs it out of the tile.
    func show(attachedTo parent: NSWindow, sidebarGlass: CGRect, tile: CGRect, visibleFrame: CGRect?) {
        let glass = Self.glassRect(edge: edge, sidebarGlass: sidebarGlass, tile: tile, height: contentHeight, visibleFrame: visibleFrame)
        panel.setGlassFrame(glass, display: false)
        parent.addChildWindow(panel, ordered: .above)
        panel.orderFrontRegardless()

        guard let view = panel.contentView else { return }
        // Pivot: the flyout's side against the sidebar, at the tile's height.
        let margins = panel.margins
        let pivotX = edge == .left ? margins.left : margins.left + glass.width
        let pivotY = margins.bottom + min(max(tile.midY - glass.minY, 0), glass.height)
        SidebarAnimation.springIn(view, pivot: CGPoint(x: pivotX, y: pivotY), offset: .zero, scale: 0.85)
    }

    func close() {
        if let parent = panel.parent { parent.removeChildWindow(panel) }
        if let view = panel.contentView { SidebarAnimation.reset(view) }
        panel.orderOut(nil)
    }

    /// Glass rectangle of the flyout: `sidebarEdgeGap` past the capsule's inner side, vertically
    /// centred on the tile, clamped to the visible frame.
    static func glassRect(edge: ScreenEdge, sidebarGlass: CGRect, tile: CGRect, height: CGFloat, visibleFrame: CGRect?) -> CGRect {
        let x = edge == .left
            ? sidebarGlass.maxX + Theme.sidebarEdgeGap
            : sidebarGlass.minX - Theme.sidebarEdgeGap - Theme.flyoutWidth
        var y = tile.midY - height / 2
        if let visible = visibleFrame {
            let minY = visible.minY + Theme.sidebarEdgeGap
            let maxY = max(minY, visible.maxY - Theme.sidebarEdgeGap - height)
            y = min(max(y, minY), maxY)
        }
        return CGRect(x: x, y: y, width: Theme.flyoutWidth, height: height)
    }
}
