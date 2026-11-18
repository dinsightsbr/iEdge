import AppKit

// Peça A: ajustar margens à ampliação máxima e ao rótulo, e a animação de entrada/saída.

/// Glass capsule window of the sidebar: non-activating (the frontmost app stays active, so paste
/// and captures act on it), above normal windows, on every Space and over full-screen apps.
final class SidebarPanel: GlassPanel {
    static let configuration = GlassPanel.Configuration(
        radius: Theme.sidebarRadius,
        // Room for the glass shadow and, horizontally, for magnified tiles growing into the screen.
        margins: NSEdgeInsets(top: 30, left: 40, bottom: 30, right: 40),
        level: .statusBar,
        collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle],
        canBecomeKey: false
    )

    /// The clipboard flyout, a child window of the sidebar.
    static let flyoutConfiguration = GlassPanel.Configuration(
        radius: Theme.flyoutRadius,
        margins: NSEdgeInsets(top: 10, left: 22, bottom: 30, right: 22),
        level: .statusBar,
        collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle],
        canBecomeKey: false
    )

    init(content: NSView) {
        super.init(content: content, configuration: Self.configuration)
    }
}
