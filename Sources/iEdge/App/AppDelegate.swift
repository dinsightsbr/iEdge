import AppKit

/// Wires the app together (docs/SPEC.md §3.1):
/// SettingsStore → ClipboardStore → ActionRunner → SidebarController → EdgeMonitor → StatusItemController.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private var settings: SettingsStore?
    private var clipboard: ClipboardStore?
    private var actions: ActionRunner?
    private var sidebar: SidebarController?
    private var edgeMonitor: EdgeMonitor?
    private var statusController: StatusItemController?

    init(options: LaunchOptions) {
        self.options = options
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
        // Writing to a `shortcuts`/`zsh` process that already exited must not kill the app.
        signal(SIGPIPE, SIG_IGN)

        let settings = SettingsStore(demo: options.demo)
        let clipboard = ClipboardStore(settings: settings, demo: options.demo)
        let actions = ActionRunner(settings: settings, clipboard: clipboard)
        let sidebar = SidebarController(settings: settings, clipboard: clipboard, actions: actions)
        let edgeMonitor = EdgeMonitor(settings: settings, isSidebarVisible: { [weak sidebar] in sidebar?.isVisible ?? false })
        edgeMonitor.onTrigger = { [weak sidebar] edge, screen, y in
            sidebar?.show(edge: edge, on: screen, atY: y)
        }
        let statusController = StatusItemController(settings: settings, sidebar: sidebar, clipboard: clipboard)
        actions.willCapture = { [weak statusController] in statusController?.closeSettings(animated: false) }

        self.settings = settings
        self.clipboard = clipboard
        self.actions = actions
        self.sidebar = sidebar
        self.edgeMonitor = edgeMonitor
        self.statusController = statusController

        clipboard.start()
        edgeMonitor.start()
        Log.app.info("iEdge iniciado\(self.options.demo ? " (demo)" : "", privacy: .public)")

        applyLaunchOptions()
    }

    /// Development aids (docs/SPEC.md §3.2), e.g. `--demo --show left --pin --hover 0.3 --flyout
    /// --frame-file /tmp/f` opens the sidebar and writes its rectangle so it can be screenshotted.
    private func applyLaunchOptions() {
        guard let sidebar, let statusController else { return }
        let options = options
        sidebar.isPinned = options.pin
        guard options.opensUIAtLaunch else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated {
                if let edge = options.show, let screen = NSScreen.main ?? NSScreen.screens.first {
                    sidebar.show(edge: edge, on: screen, atY: screen.frame.midY)
                    if let hover = options.hover { sidebar.simulateHover(fraction: hover) }
                    if options.flyout { sidebar.showFlyout() }
                }
                if let tab = options.settings {
                    statusController.showSettings(tab: tab)
                }
            }
        }
        if let path = options.frameFile {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                MainActor.assumeIsolated {
                    let lines = sidebar.panelFramesForCapture() + statusController.panelFramesForCapture()
                    do {
                        try (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
                    } catch {
                        Log.app.error("falha ao gravar --frame-file: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        edgeMonitor?.stop()
        clipboard?.stop()
        settings?.flush()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
