import SwiftUI

extension SnapshotCatalog {
    @MainActor static var sidebar: [SnapshotEntry] {
        [
            SnapshotEntry(name: "sidebar") { context in
                SidebarSnapshot.view(context, edge: .left, hover: nil)
            },
            SnapshotEntry(name: "sidebar-left") { context in
                SidebarSnapshot.view(context, edge: .left, hover: 0.3)
            },
            SnapshotEntry(name: "sidebar-right") { context in
                SidebarSnapshot.view(context, edge: .right, hover: 0.3)
            },
            SnapshotEntry(name: "sidebar-hover-top") { context in
                SidebarSnapshot.view(context, edge: .left, hover: 0.1)
            },
            SnapshotEntry(name: "sidebar-hover-mid") { context in
                SidebarSnapshot.view(context, edge: .left, hover: 0.5)
            },
            SnapshotEntry(name: "sidebar-flyout") { context in
                SidebarSnapshot.flyout(context, edge: .left)
            },
        ]
    }
}

private extension VerticalAlignment {
    /// The flyout is centred on the clipboard tile.
    enum SidebarClipboardTile: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[VerticalAlignment.center] }
    }

    static let sidebarClipboardTile = VerticalAlignment(SidebarClipboardTile.self)
}

/// The sidebar as it looks on screen, with the room its magnified tiles and label take.
@MainActor private enum SidebarSnapshot {
    static let labelRoom: CGFloat = 150

    /// `hover` is the simulated cursor as a fraction of the capsule height (like `--hover`).
    static func view(_ context: SnapshotContext, edge: ScreenEdge, hover: Double?) -> AnyView {
        let (model, _) = makeModel(context, edge: edge, hover: hover, inwardRoom: hover == nil ? 0 : labelRoom)
        return AnyView(SidebarView(settings: context.settings, model: model))
    }

    static func flyout(_ context: SnapshotContext, edge: ScreenEdge) -> AnyView {
        let current = context.settings.settings
        let items = current.enabledItems
        let clipboardIndex = items.firstIndex { $0.kind == .clipboard } ?? 0
        let (model, _) = makeModel(context, edge: edge, hover: nil, inwardRoom: 0)
        model.heldSelection = clipboardIndex
        model.showsLabel = false

        let list = ClipboardListView(store: context.clipboard, onPick: { _ in })
            .frame(width: Theme.flyoutWidth)
            .background(RoundedRectangle(cornerRadius: Theme.flyoutRadius, style: .continuous).fill(SidebarView.snapshotGlass))
        let tileCenter = Theme.sidebarPadding + CGFloat(clipboardIndex) * (current.tileSize + Theme.tileSpacing) + current.tileSize / 2

        let tileY = model.canvas.glassOrigin.y + tileCenter
        let sidebar = SidebarView(settings: context.settings, model: model)
            .alignmentGuide(VerticalAlignment.sidebarClipboardTile) { (_: ViewDimensions) -> CGFloat in tileY }
        let flyout = list.alignmentGuide(VerticalAlignment.sidebarClipboardTile) { (d: ViewDimensions) -> CGFloat in d[VerticalAlignment.center] }
        return AnyView(
            HStack(alignment: .sidebarClipboardTile, spacing: Theme.sidebarEdgeGap) {
                if edge == .left {
                    sidebar
                    flyout
                } else {
                    flyout
                    sidebar
                }
            }
        )
    }

    private static func makeModel(_ context: SnapshotContext, edge: ScreenEdge, hover: Double?, inwardRoom: CGFloat) -> (SidebarModel, CGSize) {
        let current = context.settings.settings
        let count = current.enabledItems.count
        let glass = SidebarView.glassSize(itemCount: count, tileSize: current.tileSize)
        let cursorY = hover.map { CGFloat($0) * glass.height }
        let layout = SidebarView.layout(settings: current, cursorY: cursorY)
        let above = max(0, -layout.top)
        let below = max(0, layout.top + layout.totalHeight - glass.height)
        let maxScale = layout.tiles.map(\.scale).max() ?? 1
        let overflow = max(0, (maxScale - 1) * current.tileSize - Theme.sidebarPadding)
        let inward = max(overflow, inwardRoom > 0 ? overflow + inwardRoom : 0)

        let model = SidebarModel()
        model.edge = edge
        model.cursorY = cursorY
        model.presented = true
        model.canvas = SidebarCanvas(
            size: CGSize(width: glass.width + inward, height: glass.height + above + below),
            glassOrigin: CGPoint(x: edge == .left ? 0 : inward, y: above)
        )
        return (model, glass)
    }
}
