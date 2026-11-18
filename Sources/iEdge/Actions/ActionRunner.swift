import AppKit

/// Runs sidebar items (docs/SPEC.md §1.4, §1.5). The sidebar is already closed when `perform` is
/// called, so captures never include it.
@MainActor final class ActionRunner: ActionPerforming {
    private let settings: SettingsStore
    private let clipboard: ClipboardStore
    /// Capture previews and failure notices share one card.
    let toast = CaptureToastController()
    private let screenshots: ScreenshotService
    private let custom: CustomActions

    init(settings: SettingsStore, clipboard: ClipboardStore) {
        self.settings = settings
        self.clipboard = clipboard
        self.screenshots = ScreenshotService(settings: settings, toast: toast)
        self.custom = CustomActions(toast: toast)
    }

    func perform(_ item: SidebarItem, context: ActionContext) {
        Log.actions.info("perform \(item.kind.kindTitle, privacy: .public) na borda \(context.edge.rawValue, privacy: .public)")
        switch item.kind {
        case .screenshotFull, .screenshotArea, .screenshotWindow:
            screenshots.capture(item.kind, context: context)
        case .captureTool:
            screenshots.openCaptureTool(context: context)
        case .clipboard:
            // The sidebar opens the flyout itself; nothing to run here.
            break
        case .openApp, .openURL, .shortcut, .shell:
            custom.run(item, context: context)
        }
    }
}
