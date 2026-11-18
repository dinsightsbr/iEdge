import CoreGraphics
import XCTest
@testable import iEdge

final class EdgeGeometryTests: XCTestCase {
    private let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let config = EdgeGeometry.Config()

    // MARK: Hit

    func testLeftAndRightEdgesOfASingleScreen() {
        XCTAssertEqual(EdgeGeometry.hit(at: CGPoint(x: 0, y: 450), screens: [main], config: config), .init(edge: .left, screenIndex: 0))
        XCTAssertEqual(EdgeGeometry.hit(at: CGPoint(x: 1, y: 450), screens: [main], config: config), .init(edge: .left, screenIndex: 0))
        XCTAssertEqual(EdgeGeometry.hit(at: CGPoint(x: 1439, y: 450), screens: [main], config: config), .init(edge: .right, screenIndex: 0))
        XCTAssertEqual(EdgeGeometry.hit(at: CGPoint(x: 1438, y: 450), screens: [main], config: config), .init(edge: .right, screenIndex: 0))
        XCTAssertNil(EdgeGeometry.hit(at: CGPoint(x: 2, y: 450), screens: [main], config: config))
        XCTAssertNil(EdgeGeometry.hit(at: CGPoint(x: 700, y: 450), screens: [main], config: config))
    }

    func testEdgeBetweenTwoScreensSideBySideDoesNotTrigger() {
        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let screens = [main, second]
        // Right edge of the main screen and left edge of the second one touch each other.
        XCTAssertNil(EdgeGeometry.hit(at: CGPoint(x: 1439, y: 450), screens: screens, config: config))
        XCTAssertNil(EdgeGeometry.hit(at: CGPoint(x: 1440, y: 450), screens: screens, config: config))
        // The outer edges are real.
        XCTAssertEqual(EdgeGeometry.hit(at: CGPoint(x: 0, y: 450), screens: screens, config: config), .init(edge: .left, screenIndex: 0))
        XCTAssertEqual(EdgeGeometry.hit(at: CGPoint(x: 3359, y: 500), screens: screens, config: config), .init(edge: .right, screenIndex: 1))
    }

    func testEdgeIsRealWhereTheNeighbourDoesNotReach() {
        // A taller screen on the right: above the main screen's height, its left edge is real.
        let tall = CGRect(x: 1440, y: 0, width: 1080, height: 1920)
        let screens = [main, tall]
        XCTAssertNil(EdgeGeometry.hit(at: CGPoint(x: 1440, y: 450), screens: screens, config: config))
        XCTAssertEqual(EdgeGeometry.hit(at: CGPoint(x: 1440, y: 1400), screens: screens, config: config), .init(edge: .left, screenIndex: 1))
    }

    func testCornersAreExcluded() {
        XCTAssertNil(EdgeGeometry.hit(at: CGPoint(x: 0, y: 10), screens: [main], config: config))
        XCTAssertNil(EdgeGeometry.hit(at: CGPoint(x: 0, y: 890), screens: [main], config: config))
        XCTAssertNil(EdgeGeometry.hit(at: CGPoint(x: 1439, y: 31), screens: [main], config: config))
        XCTAssertNotNil(EdgeGeometry.hit(at: CGPoint(x: 0, y: 33), screens: [main], config: config))
        XCTAssertNotNil(EdgeGeometry.hit(at: CGPoint(x: 0, y: 867), screens: [main], config: config))

        let none = EdgeGeometry.Config(cornerExclusion: 0)
        XCTAssertNotNil(EdgeGeometry.hit(at: CGPoint(x: 0, y: 10), screens: [main], config: none))
    }

    func testDockOnTheLeftExcludesThatEdgeUnlessForced() {
        let dockLeft = EdgeGeometry.Config(dockEdge: .left)
        XCTAssertNil(EdgeGeometry.hit(at: CGPoint(x: 0, y: 450), screens: [main], config: dockLeft))
        XCTAssertNotNil(EdgeGeometry.hit(at: CGPoint(x: 1439, y: 450), screens: [main], config: dockLeft))

        let forced = EdgeGeometry.Config(dockEdge: .left, forceEdgeWithDock: true)
        XCTAssertEqual(EdgeGeometry.hit(at: CGPoint(x: 0, y: 450), screens: [main], config: forced), .init(edge: .left, screenIndex: 0))
    }

    func testDisabledEdge() {
        let rightOnly = EdgeGeometry.Config(edges: [.right])
        XCTAssertNil(EdgeGeometry.hit(at: CGPoint(x: 0, y: 450), screens: [main], config: rightOnly))
        XCTAssertNotNil(EdgeGeometry.hit(at: CGPoint(x: 1439, y: 450), screens: [main], config: rightOnly))
    }

    func testScreenWithNegativeOrigin() {
        // A monitor on the left of the main screen, lower and with negative coordinates.
        let left = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        let screens = [main, left]
        XCTAssertEqual(EdgeGeometry.hit(at: CGPoint(x: -1920, y: 200), screens: screens, config: config), .init(edge: .left, screenIndex: 1))
        XCTAssertEqual(EdgeGeometry.hit(at: CGPoint(x: -1919, y: -200), screens: screens, config: config), .init(edge: .left, screenIndex: 1))
        // Its right edge touches the main screen where both overlap vertically…
        XCTAssertNil(EdgeGeometry.hit(at: CGPoint(x: -1, y: 400), screens: screens, config: config))
        XCTAssertNil(EdgeGeometry.hit(at: CGPoint(x: 0, y: 400), screens: screens, config: config))
        // …but below the main screen nothing is there, so it is a real edge.
        XCTAssertEqual(EdgeGeometry.hit(at: CGPoint(x: -1, y: -100), screens: screens, config: config), .init(edge: .right, screenIndex: 1))
        // And above the left monitor (y ≥ 780) the main screen's left edge is real.
        XCTAssertEqual(EdgeGeometry.hit(at: CGPoint(x: 0, y: 820), screens: screens, config: config), .init(edge: .left, screenIndex: 0))
    }

    func testDockOrientation() {
        XCTAssertEqual(EdgeDockSide.edge(forOrientation: "left"), .left)
        XCTAssertEqual(EdgeDockSide.edge(forOrientation: "right"), .right)
        XCTAssertNil(EdgeDockSide.edge(forOrientation: "bottom"))
        XCTAssertNil(EdgeDockSide.edge(forOrientation: nil))
    }

    // MARK: Trigger state

    private let left = EdgeGeometry.Hit(edge: .left, screenIndex: 0)
    private let right = EdgeGeometry.Hit(edge: .right, screenIndex: 0)

    func testDwellFires() {
        var state = EdgeTriggerState(dwell: 0.15, pushDistance: 14)
        XCTAssertNil(state.moved(hit: left, deltaX: -5, buttonDown: false, time: 0))
        XCTAssertEqual(state.armedHit, left)
        XCTAssertNil(state.tick(time: 0.10))
        XCTAssertEqual(state.tick(time: 0.15), left)
        // Fires once.
        XCTAssertNil(state.tick(time: 0.5))
        XCTAssertNil(state.moved(hit: left, deltaX: 0, buttonDown: false, time: 0.6))
    }

    func testDwellAlsoFiresOnALateMove() {
        var state = EdgeTriggerState(dwell: 0.15, pushDistance: 14)
        _ = state.moved(hit: left, deltaX: 0, buttonDown: false, time: 0)
        XCTAssertEqual(state.moved(hit: left, deltaX: 0, buttonDown: false, time: 0.2), left)
    }

    func testAccumulatedPushFires() {
        var state = EdgeTriggerState(dwell: 0.15, pushDistance: 14)
        // The move that reaches the edge does not count as a push.
        XCTAssertNil(state.moved(hit: left, deltaX: -40, buttonDown: false, time: 0))
        XCTAssertNil(state.moved(hit: left, deltaX: -5, buttonDown: false, time: 0.01))
        // Movement away from the edge does not subtract.
        XCTAssertNil(state.moved(hit: left, deltaX: 3, buttonDown: false, time: 0.02))
        XCTAssertNil(state.moved(hit: left, deltaX: -5, buttonDown: false, time: 0.03))
        XCTAssertEqual(state.moved(hit: left, deltaX: -5, buttonDown: false, time: 0.04), left)
    }

    func testPushOnTheRightEdgeIsPositive() {
        var state = EdgeTriggerState(dwell: 1, pushDistance: 14)
        _ = state.moved(hit: right, deltaX: 30, buttonDown: false, time: 0)
        XCTAssertNil(state.moved(hit: right, deltaX: -20, buttonDown: false, time: 0.01))
        XCTAssertNil(state.moved(hit: right, deltaX: 10, buttonDown: false, time: 0.02))
        XCTAssertEqual(state.moved(hit: right, deltaX: 5, buttonDown: false, time: 0.03), right)
    }

    func testRearmsOnlyAfterLeaving() {
        var state = EdgeTriggerState(dwell: 0.15, pushDistance: 14)
        _ = state.moved(hit: left, deltaX: 0, buttonDown: false, time: 0)
        XCTAssertEqual(state.tick(time: 0.2), left)
        // Still on the edge: pushing and waiting do nothing.
        XCTAssertNil(state.moved(hit: left, deltaX: -50, buttonDown: false, time: 0.3))
        XCTAssertNil(state.tick(time: 2))
        XCTAssertNil(state.armedHit)
        // Leave, come back: armed again.
        XCTAssertNil(state.moved(hit: nil, deltaX: 10, buttonDown: false, time: 3))
        XCTAssertNil(state.moved(hit: left, deltaX: -10, buttonDown: false, time: 3.1))
        XCTAssertEqual(state.tick(time: 3.3), left)
    }

    func testButtonHeldBlocksUntilLeaving() {
        var state = EdgeTriggerState(dwell: 0.15, pushDistance: 14)
        XCTAssertNil(state.moved(hit: left, deltaX: -30, buttonDown: true, time: 0))
        XCTAssertNil(state.tick(time: 1))
        // Released on the edge: still waits for the cursor to leave.
        XCTAssertNil(state.moved(hit: left, deltaX: -30, buttonDown: false, time: 1.1))
        XCTAssertNil(state.tick(time: 2))
        _ = state.moved(hit: nil, deltaX: 5, buttonDown: false, time: 3)
        _ = state.moved(hit: left, deltaX: -5, buttonDown: false, time: 3.1)
        XCTAssertEqual(state.tick(time: 3.3), left)
    }

    func testMovingToAnotherEdgeRestartsTheCount() {
        var state = EdgeTriggerState(dwell: 0.15, pushDistance: 14)
        _ = state.moved(hit: left, deltaX: 0, buttonDown: false, time: 0)
        XCTAssertNil(state.moved(hit: right, deltaX: 0, buttonDown: false, time: 0.1))
        XCTAssertNil(state.tick(time: 0.2))
        XCTAssertEqual(state.tick(time: 0.25), right)
    }

    func testLatchWhileTheSidebarIsOpen() {
        var state = EdgeTriggerState(dwell: 0.15, pushDistance: 14)
        state.latch(left)
        XCTAssertNil(state.moved(hit: left, deltaX: -50, buttonDown: false, time: 0))
        XCTAssertNil(state.tick(time: 1))
        state.latch(nil)
        _ = state.moved(hit: left, deltaX: 0, buttonDown: false, time: 2)
        XCTAssertEqual(state.tick(time: 2.2), left)
    }
}
