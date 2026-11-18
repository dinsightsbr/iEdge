import CoreGraphics
import Foundation

/// The sidebar's vertical magnifier, like the Dock's (docs/SPEC.md §1.2). Pure, so it is tested
/// without a window.
///
/// Coordinates are local to the glass capsule, y growing downwards from its top. At rest the
/// tiles sit `padding` from the capsule, `spacing` apart. With a cursor, each tile scales by
/// `1 + (m - 1) · exp(-d² / 2σ²)` (d = distance from the cursor to the tile's resting centre,
/// σ = 1.2 × tileSize), and the scaled tiles push their neighbours apart. The stack is then shifted
/// so the spot under the cursor stays under it, which keeps the magnified tile in place while
/// the others make room above and below.
struct Magnification: Equatable {
    struct Tile: Equatable {
        /// Centre of the tile, from the capsule's top.
        var centerY: CGFloat
        var scale: CGFloat
        /// Diameter of the scaled tile.
        var size: CGFloat
    }

    var tiles: [Tile]
    /// Height from the top of the first tile's padding to the bottom of the last (the resting
    /// capsule height without a cursor; larger while magnifying).
    var totalHeight: CGFloat
    /// Top of that span relative to the capsule's top (negative when tiles overflow upwards).
    var top: CGFloat
    /// Tile nearest to the cursor while the cursor is over the stack.
    var selectedIndex: Int?

    static let sigmaFactor: CGFloat = 1.2

    /// - Parameters:
    ///   - cursorY: the cursor from the capsule's top, or nil when it is not over the sidebar.
    ///   - selectionSlack: how far above the first and below the last tile the cursor still selects.
    init(
        count: Int,
        tileSize: CGFloat,
        magnification: CGFloat,
        cursorY: CGFloat?,
        spacing: CGFloat = Theme.tileSpacing,
        padding: CGFloat = Theme.sidebarPadding,
        selectionSlack: CGFloat = Theme.tileSpacing
    ) {
        let count = max(count, 0)
        let pitch = tileSize + spacing
        let restCenters = (0..<count).map { padding + CGFloat($0) * pitch + tileSize / 2 }
        let restHeight = Self.restingHeight(count: count, tileSize: tileSize, spacing: spacing, padding: padding)

        guard let cursorY, count > 0 else {
            tiles = restCenters.map { Tile(centerY: $0, scale: 1, size: tileSize) }
            totalHeight = restHeight
            top = 0
            selectedIndex = nil
            return
        }

        let sigma = Self.sigmaFactor * tileSize
        let gain = max(magnification, 1) - 1
        let scales = restCenters.map { center -> CGFloat in
            let d = cursorY - center
            return 1 + gain * exp(-(d * d) / (2 * sigma * sigma))
        }
        let sizes = scales.map { $0 * tileSize }

        // Lay the scaled tiles out from the top, gaps and padding unchanged.
        var centers: [CGFloat] = []
        var y = padding
        for size in sizes {
            centers.append(y + size / 2)
            y += size + spacing
        }
        let height = y - spacing + padding

        // Map the cursor to the same relative spot in the scaled stack: inside a tile it keeps its
        // fraction of that tile; in a gap or the padding it keeps its offset from the tile above.
        let mapped: CGFloat
        if let index = restCenters.indices.last(where: { cursorY >= restCenters[$0] - tileSize / 2 }) {
            let restTop = restCenters[index] - tileSize / 2
            let offset = cursorY - restTop
            let scaledTop = centers[index] - sizes[index] / 2
            mapped = offset <= tileSize
                ? scaledTop + offset / tileSize * sizes[index]
                : scaledTop + sizes[index] + (offset - tileSize)
        } else {
            mapped = cursorY
        }
        let shift = cursorY - mapped

        tiles = (0..<count).map { Tile(centerY: centers[$0] + shift, scale: scales[$0], size: sizes[$0]) }
        totalHeight = height
        top = shift

        let first = restCenters[0] - tileSize / 2 - selectionSlack
        let last = restCenters[count - 1] + tileSize / 2 + selectionSlack
        if cursorY >= first, cursorY <= last {
            selectedIndex = restCenters.indices.min { abs(restCenters[$0] - cursorY) < abs(restCenters[$1] - cursorY) }
        } else {
            selectedIndex = nil
        }
    }

    /// Capsule height at rest: tiles, the gaps between them and the padding.
    static func restingHeight(count: Int, tileSize: CGFloat, spacing: CGFloat = Theme.tileSpacing, padding: CGFloat = Theme.sidebarPadding) -> CGFloat {
        let n = CGFloat(max(count, 1))
        return n * tileSize + (n - 1) * spacing + 2 * padding
    }

    /// Horizontal offset of a scaled tile's centre: it grows into the screen, anchored on the
    /// edge side (positive x = right, so it is negative on the right edge).
    static func inwardOffset(scale: CGFloat, tileSize: CGFloat, edge: ScreenEdge) -> CGFloat {
        let grow = (scale - 1) * tileSize / 2
        return edge == .left ? grow : -grow
    }

    /// Largest growth of the whole stack above or below the capsule, for sizing the window.
    static func maxOverflow(count: Int, tileSize: CGFloat, magnification: CGFloat) -> CGFloat {
        // The stack grows by at most the sum of all tiles' growth (cursor beyond one end pushes
        // everything to the other side).
        let sigma = sigmaFactor * tileSize
        let pitch = tileSize + Theme.tileSpacing
        let gain = max(magnification, 1) - 1
        let growth = (0..<max(count, 0)).reduce(CGFloat(0)) { sum, i in
            let d = CGFloat(i) * pitch
            return sum + gain * tileSize * exp(-(d * d) / (2 * sigma * sigma))
        }
        return growth
    }
}
