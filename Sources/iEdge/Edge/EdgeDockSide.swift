import Foundation

/// Which side the Dock sits on (`com.apple.dock` `orientation`). The edge the Dock uses does not
/// trigger the sidebar unless `forceEdgeWithDock` is on (docs/SPEC.md §1.1).
enum EdgeDockSide {
    /// The screen edge the Dock occupies, or nil when it sits at the bottom.
    static func current() -> ScreenEdge? {
        edge(forOrientation: UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation"))
    }

    static func edge(forOrientation orientation: String?) -> ScreenEdge? {
        switch orientation {
        case "left": return .left
        case "right": return .right
        default: return nil
        }
    }
}
