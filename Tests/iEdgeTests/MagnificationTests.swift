import CoreGraphics
import XCTest
@testable import iEdge

final class MagnificationTests: XCTestCase {
    private let tile: CGFloat = 44
    private let spacing: CGFloat = 8
    private let padding: CGFloat = 10

    private func layout(count: Int = 5, magnification: CGFloat = 1.6, cursorY: CGFloat?) -> Magnification {
        Magnification(count: count, tileSize: tile, magnification: magnification, cursorY: cursorY, spacing: spacing, padding: padding)
    }

    /// Resting centre of tile `index` from the capsule's top.
    private func restCenter(_ index: Int) -> CGFloat {
        padding + CGFloat(index) * (tile + spacing) + tile / 2
    }

    func testWithoutCursorEverythingRests() {
        let result = layout(cursorY: nil)
        XCTAssertEqual(result.tiles.map(\.scale), Array(repeating: 1, count: 5))
        XCTAssertEqual(result.tiles.map(\.centerY), (0..<5).map(restCenter))
        XCTAssertEqual(result.totalHeight, 5 * 44 + 4 * 8 + 20)
        XCTAssertEqual(result.top, 0)
        XCTAssertNil(result.selectedIndex)
    }

    func testCursorOnATileCentreMagnifiesItMostAndSymmetrically() {
        let result = layout(cursorY: restCenter(2))
        XCTAssertEqual(result.tiles[2].scale, 1.6, accuracy: 1e-9)
        XCTAssertEqual(result.tiles[2].size, 1.6 * 44, accuracy: 1e-9)
        XCTAssertTrue(result.tiles.allSatisfy { $0.scale <= result.tiles[2].scale })
        XCTAssertEqual(result.tiles[1].scale, result.tiles[3].scale, accuracy: 1e-9)
        XCTAssertEqual(result.tiles[0].scale, result.tiles[4].scale, accuracy: 1e-9)
        XCTAssertGreaterThan(result.tiles[1].scale, result.tiles[0].scale)
        // The magnified tile stays under the cursor and the neighbours move apart evenly.
        XCTAssertEqual(result.tiles[2].centerY, restCenter(2), accuracy: 1e-9)
        XCTAssertEqual(result.tiles[2].centerY - result.tiles[1].centerY, result.tiles[3].centerY - result.tiles[2].centerY, accuracy: 1e-9)
        XCTAssertGreaterThan(result.tiles[3].centerY - result.tiles[2].centerY, tile + spacing)
        XCTAssertEqual(result.selectedIndex, 2)
    }

    func testScaleFollowsTheGaussian() {
        let result = layout(cursorY: restCenter(2))
        let sigma = 1.2 * tile
        let d = tile + spacing
        XCTAssertEqual(result.tiles[3].scale, 1 + 0.6 * exp(-(d * d) / (2 * sigma * sigma)), accuracy: 1e-9)
    }

    func testNeighboursAreNotOverlapped() {
        for cursor in stride(from: CGFloat(-20), through: 300, by: 7) {
            let tiles = layout(cursorY: cursor).tiles
            for (a, b) in zip(tiles, tiles.dropFirst()) {
                XCTAssertEqual(b.centerY - b.size / 2 - (a.centerY + a.size / 2), spacing, accuracy: 1e-9)
            }
        }
    }

    func testTotalHeightGrowsWithMagnification() {
        let rest = layout(cursorY: nil).totalHeight
        let mild = layout(magnification: 1.3, cursorY: restCenter(2)).totalHeight
        let strong = layout(magnification: 2.0, cursorY: restCenter(2)).totalHeight
        XCTAssertGreaterThan(mild, rest)
        XCTAssertGreaterThan(strong, mild)
        // Magnification 1 changes nothing.
        let none = layout(magnification: 1.0, cursorY: restCenter(2))
        XCTAssertEqual(none.totalHeight, rest, accuracy: 1e-9)
        XCTAssertEqual(none.tiles.map(\.centerY), (0..<5).map(restCenter))
    }

    func testSelectedIndexIsTheNearestTile() {
        XCTAssertEqual(layout(cursorY: restCenter(0)).selectedIndex, 0)
        XCTAssertEqual(layout(cursorY: restCenter(1) + 20).selectedIndex, 1)
        XCTAssertEqual(layout(cursorY: restCenter(1) + 30).selectedIndex, 2)
        XCTAssertEqual(layout(cursorY: restCenter(4) + 22 + 5).selectedIndex, 4)
        // Well above or below the stack: nothing selected, but still a (fading) magnifier.
        XCTAssertNil(layout(cursorY: -40).selectedIndex)
        XCTAssertNil(layout(cursorY: 400).selectedIndex)
        XCTAssertGreaterThan(layout(cursorY: -40).tiles[0].scale, 1)
    }

    func testStackIsContinuousAcrossTileBoundaries() {
        // Moving the cursor by a hair never makes the tiles jump.
        for cursor in stride(from: CGFloat(-30), through: 300, by: 0.5) {
            let a = layout(cursorY: cursor).tiles
            let b = layout(cursorY: cursor + 0.01).tiles
            for (x, y) in zip(a, b) {
                XCTAssertEqual(x.centerY, y.centerY, accuracy: 0.05, "cursor \(cursor)")
            }
        }
    }

    func testMirroringDoesNotChangeTheVertical() {
        let result = layout(cursorY: restCenter(1) + 5)
        for tile in result.tiles {
            let left = Magnification.inwardOffset(scale: tile.scale, tileSize: self.tile, edge: .left)
            let right = Magnification.inwardOffset(scale: tile.scale, tileSize: self.tile, edge: .right)
            XCTAssertEqual(left, -right)
            XCTAssertGreaterThanOrEqual(left, 0)
            // Anchored on the edge side: the outer side stays where it was.
            XCTAssertEqual(left - tile.size / 2, -self.tile / 2, accuracy: 1e-9)
        }
        let glass = CGRect(x: 0, y: 0, width: 64, height: Magnification.restingHeight(count: 5, tileSize: tile))
        let mirrored = CGRect(x: 1000, y: 0, width: 64, height: glass.height)
        for tile in result.tiles {
            let l = SidebarView.tileRect(tile, glass: glass, tileSize: self.tile, edge: .left)
            let r = SidebarView.tileRect(tile, glass: mirrored, tileSize: self.tile, edge: .right)
            XCTAssertEqual(l.minY, r.minY, accuracy: 1e-9)
            XCTAssertEqual(l.height, r.height, accuracy: 1e-9)
            XCTAssertEqual(l.minX - glass.minX, mirrored.maxX - r.maxX, accuracy: 1e-9)
        }
    }

    func testEmptyStack() {
        let result = layout(count: 0, cursorY: 30)
        XCTAssertTrue(result.tiles.isEmpty)
        XCTAssertNil(result.selectedIndex)
    }

    func testMaxOverflowCoversTheLargestSettings() {
        let worst = Magnification.maxOverflow(count: 12, tileSize: 56, magnification: 2)
        XCTAssertLessThan(worst, SidebarPanel.verticalMargin)
        for count in 1...12 {
            let glassHeight = Magnification.restingHeight(count: count, tileSize: 56)
            for cursor in stride(from: CGFloat(-60), through: glassHeight + 60, by: 4) {
                let result = Magnification(count: count, tileSize: 56, magnification: 2, cursorY: cursor)
                XCTAssertGreaterThanOrEqual(result.top, -SidebarPanel.verticalMargin)
                XCTAssertLessThanOrEqual(result.top + result.totalHeight - glassHeight, SidebarPanel.verticalMargin)
            }
        }
    }
}
