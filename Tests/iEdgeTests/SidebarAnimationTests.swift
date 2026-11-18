import XCTest
@testable import iEdge

@MainActor final class SidebarAnimationTests: XCTestCase {
    func testDampingForOvershootRoundTrips() {
        for (overshoot, travel) in [(6.0, 72.0), (6.0, 84.0), (2.0, 50.0), (10.0, 60.0)] {
            let damping = SidebarAnimation.damping(forOvershoot: CGFloat(overshoot), travel: CGFloat(travel))
            XCTAssertGreaterThan(damping, 0)
            XCTAssertLessThan(damping, 1)
            XCTAssertEqual(SidebarAnimation.overshootFraction(damping: damping) * travel, overshoot, accuracy: 1e-9)
        }
    }

    func testSidebarEntryPassesAboutSixPoints() {
        // The sidebar travels its glass width plus the edge gap (default 44 pt tiles: 72 pt).
        let travel = 44 + 2 * Theme.sidebarPadding + Theme.sidebarEdgeGap
        let damping = SidebarAnimation.damping(forOvershoot: SidebarAnimation.entryOvershoot, travel: travel)
        XCTAssertEqual(damping, 0.62, accuracy: 0.01)
        // The spec's damping 0.72 alone would pass only ~3 pt over that travel.
        XCTAssertEqual(SidebarAnimation.overshootFraction(damping: SidebarAnimation.damping) * Double(travel), 2.7, accuracy: 0.2)
    }

    func testDegenerateInputsDoNotBounce() {
        XCTAssertEqual(SidebarAnimation.damping(forOvershoot: 0, travel: 72), 1)
        XCTAssertEqual(SidebarAnimation.damping(forOvershoot: 6, travel: 0), 1)
        XCTAssertEqual(SidebarAnimation.overshootFraction(damping: 1), 0)
    }
}
