import AppKit

// Contract between the sidebar (piece A) and the actions (piece B). Do not change these
// signatures; add members if needed.

/// Where an item was triggered from: the edge, the screen the sidebar was on, and the tile's
/// rectangle in screen coordinates (anchor for toasts and popovers).
struct ActionContext {
    var edge: ScreenEdge
    var screen: NSScreen
    var anchor: CGRect
}

@MainActor protocol ActionPerforming: AnyObject {
    /// Called with the sidebar already closed (except for `.clipboard`, which the sidebar handles).
    func perform(_ item: SidebarItem, context: ActionContext)
}
