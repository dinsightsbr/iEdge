import SwiftUI

/// Visual language shared by every panel: system colors and the flat, grouped look of Control Center.
enum Theme {
    // MARK: Panels (Settings, flyout, toast)

    /// Corner radius of the Settings panel (Control Center modules on macOS 26).
    static let panelRadius: CGFloat = 18
    /// Inset of text from the panel edge; rows add their own padding to reach it.
    static let contentInset: CGFloat = 18
    /// Rows sit `rowOutset` inside the panel, so `panelRadius = rowRadius + rowOutset`.
    static let rowOutset: CGFloat = 8
    static let rowRadius: CGFloat = 10
    static let cardRadius: CGFloat = 12

    static let settingsWidth: CGFloat = 400
    static let flyoutWidth: CGFloat = 300
    static let flyoutRadius: CGFloat = 18
    static let toastRadius: CGFloat = 16

    // MARK: Sidebar

    static let sidebarRadius: CGFloat = 22
    /// Gap between the screen edge and the glass capsule.
    static let sidebarEdgeGap: CGFloat = 8
    /// Padding between the capsule and its tiles (width = tile + 2 × padding).
    static let sidebarPadding: CGFloat = 10
    static let tileSpacing: CGFloat = 8
    static let tileSymbolSize: CGFloat = 18

    // MARK: Colors

    static let accent = Color.accentColor
    static let warning = Color.orange
    static let critical = Color.red
    static let ok = Color.green

    /// Grouped section behind forms and detail rows (no border, like Control Center bands).
    static let cardFill = Color.primary.opacity(0.05)
    static let hoverFill = Color.primary.opacity(0.05)
    static let selectedFill = Color.primary.opacity(0.08)
    static let tileFill = Color.primary.opacity(0.08)
    static let track = Color.primary.opacity(0.10)
}
