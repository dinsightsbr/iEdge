import AppKit
import SwiftUI

/// What the sidebar's tiles show at the moment; driven by the controller's display link.
@MainActor final class SidebarModel: ObservableObject {
    @Published var edge: ScreenEdge = .left
    /// Cursor from the top of the glass, or nil when it is not over the sidebar.
    @Published var cursorY: CGFloat?
    /// False while the tiles wait to cascade in.
    @Published var presented = true
    /// Whether changes of `presented` animate (only the entry cascades).
    var animatesCascade = false
    /// Tile shown selected while the cursor is elsewhere (the clipboard tile, with its flyout open).
    @Published var heldSelection: Int?
    /// False while the flyout covers the label's place.
    @Published var showsLabel = true
    /// Tile the cascade starts from (nearest to the cursor at the trigger).
    var cascadeOrigin = 0
    /// Size of the drawing area and the top-left of the glass inside it (top-down coordinates).
    @Published var canvas = SidebarCanvas(size: .zero, glassOrigin: .zero)
}

struct SidebarCanvas: Equatable {
    var size: CGSize
    var glassOrigin: CGPoint
}

/// Tiles of the sidebar over (and spilling past) the glass capsule, with the magnifier, the
/// selected tile in the accent colour and its label beside it, into the screen.
struct SidebarView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: SidebarModel
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        let current = settings.settings
        let items = current.enabledItems
        let tileSize = current.tileSize
        let magnification = SidebarView.layout(settings: current, cursorY: model.cursorY)
        let glassSize = SidebarView.glassSize(itemCount: items.count, tileSize: tileSize)
        let origin = model.canvas.glassOrigin
        let edge = model.edge
        let restX = origin.x + Theme.sidebarPadding + tileSize / 2
        let selectedIndex = magnification.selectedIndex ?? model.heldSelection

        ZStack(alignment: .topLeading) {
            // The capsule follows the magnified stack, its centre fixed (like the Dock). It is a
            // frame of fixed width and animatable height, so it moves with the tiles in the same
            // transaction (and eases with them when the cursor enters or leaves).
            SidebarCapsule()
                .frame(width: glassSize.width, height: magnification.totalHeight)
                .offset(x: origin.x, y: origin.y + magnification.top)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let tile = magnification.tiles[index]
                let x = restX + Magnification.inwardOffset(scale: tile.scale, tileSize: tileSize, edge: edge)
                SidebarTile(item: item, size: tile.size, baseSize: tileSize, selected: index == selectedIndex)
                    .modifier(CascadeIn(
                        presented: model.presented,
                        animated: model.animatesCascade,
                        delay: Double(abs(index - model.cascadeOrigin)) * 0.015,
                        edge: edge
                    ))
                    .position(x: x, y: origin.y + tile.centerY)
            }

            if current.showLabels, model.showsLabel, let selected = selectedIndex, items.indices.contains(selected) {
                let tile = magnification.tiles[selected]
                let x = restX + Magnification.inwardOffset(scale: tile.scale, tileSize: tileSize, edge: edge)
                let inner = edge == .left ? x + tile.size / 2 + Theme.sidebarLabelGap : x - tile.size / 2 - Theme.sidebarLabelGap
                SidebarLabel(title: items[selected].title)
                    .frame(width: Theme.sidebarLabelMaxWidth, alignment: edge == .left ? .leading : .trailing)
                    .position(
                        x: edge == .left ? inner + Theme.sidebarLabelMaxWidth / 2 : inner - Theme.sidebarLabelMaxWidth / 2,
                        y: origin.y + tile.centerY
                    )
                    .opacity(model.presented ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: model.canvas.size.width, height: model.canvas.size.height, alignment: .topLeading)
        // Entering or leaving the sidebar eases the magnifier in and out instead of jumping.
        .animation(.easeOut(duration: 0.14), value: model.cursorY == nil)
        .accessibilityElement(children: .contain)
    }

    static var snapshotGlass: Color { Color.gray.opacity(0.22) }

    // MARK: Layout (shared with the controller, which positions the window and the anchors)

    /// The magnifier as the sidebar draws it: centred on the resting capsule, which grows with it.
    static func layout(settings: AppSettings, cursorY: CGFloat?, selectionSlack: CGFloat = Theme.tileSpacing) -> Magnification {
        Magnification(
            count: settings.enabledItems.count,
            tileSize: settings.tileSize,
            magnification: settings.magnification,
            cursorY: cursorY,
            selectionSlack: selectionSlack,
            anchor: .center
        )
    }

    /// The capsule for a layout, in screen coordinates (y up), from the resting `glass`: same
    /// width and centre, the height of the magnified stack.
    static func capsuleRect(_ layout: Magnification, glass: CGRect) -> CGRect {
        CGRect(x: glass.minX, y: glass.maxY - layout.top - layout.totalHeight, width: glass.width, height: layout.totalHeight)
    }

    static func glassSize(itemCount: Int, tileSize: CGFloat) -> CGSize {
        CGSize(
            width: tileSize + 2 * Theme.sidebarPadding,
            height: Magnification.restingHeight(count: itemCount, tileSize: tileSize)
        )
    }

    /// Rectangle of tile `index` (0 = top) at rest, for a glass rectangle in screen coordinates (y up).
    static func tileRect(index: Int, glass: CGRect, tileSize: CGFloat) -> CGRect {
        let top = glass.maxY - Theme.sidebarPadding - CGFloat(index) * (tileSize + Theme.tileSpacing)
        return CGRect(x: glass.minX + Theme.sidebarPadding, y: top - tileSize, width: tileSize, height: tileSize)
    }

    /// Rectangle of a magnified tile in screen coordinates.
    static func tileRect(_ tile: Magnification.Tile, glass: CGRect, tileSize: CGFloat, edge: ScreenEdge) -> CGRect {
        let centerX = glass.minX + Theme.sidebarPadding + tileSize / 2
            + Magnification.inwardOffset(scale: tile.scale, tileSize: tileSize, edge: edge)
        let centerY = glass.maxY - tile.centerY
        return CGRect(x: centerX - tile.size / 2, y: centerY - tile.size / 2, width: tile.size, height: tile.size)
    }
}

extension Theme {
    static let sidebarLabelGap: CGFloat = 8
    static let sidebarLabelMaxWidth: CGFloat = 200
    static let sidebarLabelHeight: CGFloat = 26
    static let sidebarLabelFont = NSFont.systemFont(ofSize: 12, weight: .medium)
}

/// Each tile springs in from the edge, a little after the one before it.
private struct CascadeIn: ViewModifier {
    let presented: Bool
    let animated: Bool
    let delay: Double
    let edge: ScreenEdge

    func body(content: Content) -> some View {
        content
            .scaleEffect(presented ? 1 : 0.5, anchor: edge == .left ? .leading : .trailing)
            .offset(x: presented ? 0 : (edge == .left ? -10 : 10))
            .opacity(presented ? 1 : 0)
            .animation(animated ? SidebarAnimation.swiftUISpring.delay(delay) : nil, value: presented)
    }
}

struct SidebarTile: View {
    let item: SidebarItem
    /// Current (possibly magnified) diameter.
    let size: CGFloat
    /// Diameter at rest (`tileSize`); the symbol keeps its proportion to it.
    var baseSize: CGFloat
    var selected = false

    init(item: SidebarItem, size: CGFloat, baseSize: CGFloat? = nil, selected: Bool = false) {
        self.item = item
        self.size = size
        self.baseSize = baseSize ?? size
        self.selected = selected
    }

    var body: some View {
        ZStack {
            Circle().fill(selected ? Theme.accent : Theme.tileFill)
            icon
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .accessibilityLabel(item.title)
    }

    @ViewBuilder
    private var icon: some View {
        if case .openApp(let path) = item.kind {
            Image(nsImage: SidebarAppIcons.icon(for: path))
                .resizable()
                .interpolation(.high)
                .frame(width: size * 0.72, height: size * 0.72)
        } else {
            // 18 pt at the default 44 pt tile, scaled with the tile.
            Image(systemName: item.symbol)
                .font(.system(size: Theme.tileSymbolSize * size / 44, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
    }
}

/// The sidebar's glass capsule (Liquid Glass on macOS 26, a material before; a gray stand-in in
/// snapshots, where glass does not render). Purely decorative: the overlay takes the clicks.
private struct SidebarCapsule: View {
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.sidebarRadius, style: .continuous)
        if isSnapshot {
            shape.fill(SidebarView.snapshotGlass)
        } else if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            Color.clear.background(.regularMaterial, in: shape)
        }
    }
}

/// Small glass capsule with the selected item's name.
private struct SidebarLabel: View {
    let title: String
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        let text = Text(title)
            .font(Font(Theme.sidebarLabelFont))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .frame(height: Theme.sidebarLabelHeight)
        if isSnapshot {
            text.background(Capsule().fill(SidebarView.snapshotGlass))
        } else if #available(macOS 26.0, *) {
            text.glassEffect(.regular, in: Capsule())
        } else {
            text.background(.regularMaterial, in: Capsule())
        }
    }
}

/// App icons are read once per path; the tiles redraw on every display-link frame.
@MainActor private enum SidebarAppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for path: String) -> NSImage {
        if let icon = cache[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[path] = icon
        return icon
    }
}
