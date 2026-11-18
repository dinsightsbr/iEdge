import CoreGraphics

/// Pure edge geometry (docs/SPEC.md §1.1), kept free of AppKit so it can be tested with plain
/// rectangles. Coordinates are AppKit screen coordinates (y up, origin at the bottom-left of the
/// primary screen; screens on the left have negative x).
enum EdgeGeometry {
    /// Settings that decide whether an edge may trigger.
    struct Config: Equatable {
        var edges: Set<ScreenEdge> = [.left, .right]
        var cornerExclusion: CGFloat = 32
        /// Side the Dock sits on, if left or right.
        var dockEdge: ScreenEdge?
        var forceEdgeWithDock = false

        init(edges: Set<ScreenEdge> = [.left, .right], cornerExclusion: CGFloat = 32, dockEdge: ScreenEdge? = nil, forceEdgeWithDock: Bool = false) {
            self.edges = edges
            self.cornerExclusion = cornerExclusion
            self.dockEdge = dockEdge
            self.forceEdgeWithDock = forceEdgeWithDock
        }
    }

    /// A point resting on a real, enabled edge of `screenIndex`.
    struct Hit: Equatable {
        var edge: ScreenEdge
        var screenIndex: Int
    }

    /// Index of the screen whose frame contains `point`. The maximum x and y are included,
    /// because the cursor can sit on the last column/row of a screen with nothing beyond it.
    static func screenIndex(containing point: CGPoint, screens: [CGRect]) -> Int? {
        if let index = screens.firstIndex(where: { $0.contains(point) }) { return index }
        return screens.firstIndex { point.x >= $0.minX && point.x <= $0.maxX && point.y >= $0.minY && point.y <= $0.maxY }
    }

    /// Edge the point touches on `screen`: `x <= minX + 1` or `x >= maxX - 2`.
    static func touchedEdge(_ point: CGPoint, screen: CGRect) -> ScreenEdge? {
        if point.x <= screen.minX + 1 { return .left }
        if point.x >= screen.maxX - 2 { return .right }
        return nil
    }

    /// True when another screen touches `edge` of `screen` at height `y`: the cursor would cross
    /// over to it, so that edge is not a real one there.
    static func hasNeighbor(on edge: ScreenEdge, of screen: CGRect, atY y: CGFloat, screens: [CGRect]) -> Bool {
        let tolerance: CGFloat = 1
        return screens.contains { other in
            guard other != screen, y >= other.minY, y < other.maxY else { return false }
            switch edge {
            case .left: return abs(other.maxX - screen.minX) <= tolerance
            case .right: return abs(other.minX - screen.maxX) <= tolerance
            }
        }
    }

    /// True within `cornerExclusion` of the top or bottom of the screen.
    static func isInCorner(y: CGFloat, screen: CGRect, exclusion: CGFloat) -> Bool {
        y < screen.minY + exclusion || y > screen.maxY - exclusion
    }

    /// The edge `point` triggers, or nil when it is not on a real, enabled edge outside the
    /// corners and away from the Dock.
    static func hit(at point: CGPoint, screens: [CGRect], config: Config) -> Hit? {
        guard let index = screenIndex(containing: point, screens: screens) else { return nil }
        let screen = screens[index]
        guard let edge = touchedEdge(point, screen: screen),
              config.edges.contains(edge),
              !isInCorner(y: point.y, screen: screen, exclusion: config.cornerExclusion),
              config.forceEdgeWithDock || config.dockEdge != edge,
              !hasNeighbor(on: edge, of: screen, atY: point.y, screens: screens)
        else { return nil }
        return Hit(edge: edge, screenIndex: index)
    }
}

/// When to open the sidebar while the cursor rests on an edge (docs/SPEC.md §1.1). Pure: it is
/// fed the edge under the cursor, the horizontal movement and the time, and says when to fire.
///
/// - On an edge, it fires once the cursor has stayed `dwell` seconds, or once the movement
///   pushing into the edge adds up to more than `pushDistance`.
/// - After firing, or while a mouse button is held there, it waits for the cursor to leave the
///   edge before arming again (no reopening in a loop, no popping up after dragging a window).
struct EdgeTriggerState: Equatable {
    enum Phase: Equatable {
        case idle
        case armed(EdgeGeometry.Hit, since: Double, pushed: CGFloat)
        /// Fired or blocked; waits for the cursor to leave this edge.
        case latched(EdgeGeometry.Hit)
    }

    var dwell: Double = 0.150
    var pushDistance: CGFloat = 14
    private(set) var phase: Phase = .idle

    init(dwell: Double = 0.150, pushDistance: CGFloat = 14) {
        self.dwell = dwell
        self.pushDistance = pushDistance
    }

    /// The edge being waited on, if any (the monitor runs its dwell timer only then).
    var armedHit: EdgeGeometry.Hit? {
        if case .armed(let hit, _, _) = phase { return hit }
        return nil
    }

    /// The cursor moved. `hit` is the edge under it (nil off the edges), `deltaX` the event's
    /// horizontal movement, `buttonDown` whether a mouse button is held. Returns the hit to fire.
    mutating func moved(hit: EdgeGeometry.Hit?, deltaX: CGFloat, buttonDown: Bool, time: Double) -> EdgeGeometry.Hit? {
        guard let hit else {
            phase = .idle
            return nil
        }
        if buttonDown {
            phase = .latched(hit)
            return nil
        }
        switch phase {
        case .latched(let latched) where latched == hit:
            return nil
        case .armed(let armed, let since, let pushed) where armed == hit:
            let push = hit.edge == .left ? -deltaX : deltaX
            let total = pushed + max(push, 0)
            if total > pushDistance || time - since >= dwell {
                phase = .latched(hit)
                return hit
            }
            phase = .armed(hit, since: since, pushed: total)
            return nil
        default:
            // Entering an edge (or moving to another one): only start counting. The movement
            // that brought the cursor here is not a push against the edge.
            phase = .armed(hit, since: time, pushed: 0)
            return nil
        }
    }

    /// Time passed without movement (the dwell timer). Returns the hit to fire.
    mutating func tick(time: Double) -> EdgeGeometry.Hit? {
        guard case .armed(let hit, let since, _) = phase, time - since >= dwell else { return nil }
        phase = .latched(hit)
        return hit
    }

    /// The sidebar is open (or was opened some other way): the edge under the cursor must not
    /// fire until the cursor leaves it.
    mutating func latch(_ hit: EdgeGeometry.Hit?) {
        phase = hit.map { .latched($0) } ?? .idle
    }

    mutating func reset() {
        phase = .idle
    }
}
