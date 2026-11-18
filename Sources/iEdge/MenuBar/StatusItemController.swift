import AppKit
import Combine
import SwiftUI

/// Owns the menu-bar icon: left click toggles Settings in a glass panel under it, right click
/// shows the quick menu. The panel hugs the height of its content and closes on Esc, on a click
/// elsewhere and when another app takes focus, as in iSessions.
@MainActor final class StatusItemController: NSObject, NSWindowDelegate {
    private let settings: SettingsStore
    private let sidebar: SidebarController
    private let clipboard: ClipboardStore
    private let statusItem: NSStatusItem
    private let navigation = SettingsNavigation()
    private let permissions = PermissionCenter()
    private let loginItem: LoginItem
    private let panel: GlassPanel
    private let hostingView: NSHostingView<SettingsRootView>
    private let heightRelay = SettingsHeightRelay()
    private var cancellables = Set<AnyCancellable>()
    private var clickMonitor: Any?
    private var menuTracking = false
    /// Clicking the icon while the panel is open closes it on mouse-down and would reopen it on
    /// mouse-up; remembering when it closed avoids the flicker.
    private var lastClosedAt: Date = .distantPast
    /// Last height the SwiftUI content asked for; the panel hugs it, anchored to its top edge.
    private var contentHeight: CGFloat = 360
    /// Keeps a sidebar opened from the menu or "Testar" on screen for `sidebarHold`.
    private var holdTimer: Timer?

    private static let sidebarHold: TimeInterval = 4

    private static let gapBelowMenuBar: CGFloat = 6
    private static let screenMargin: CGFloat = 8
    private static let symbolName = "sidebar.squares.left"

    init(settings: SettingsStore, sidebar: SidebarController, clipboard: ClipboardStore) {
        self.settings = settings
        self.sidebar = sidebar
        self.clipboard = clipboard
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let loginItem = LoginItem(live: !settings.isDemo, initiallyEnabled: settings.settings.launchAtLogin)
        self.loginItem = loginItem

        let relay = heightRelay
        let root = SettingsRootView(
            settings: settings,
            navigation: navigation,
            clipboard: clipboard,
            permissions: permissions,
            loginItem: loginItem,
            maxContentHeight: Self.maxContentHeight(),
            onTestEdge: { edge in relay.testEdge?(edge) },
            onQuit: { NSApp.terminate(nil) },
            onHeightChange: { relay.heightChanged?($0) }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        self.hostingView = hosting
        self.panel = GlassPanel(content: hosting, configuration: .settings)
        super.init()

        relay.heightChanged = { [weak self] height in self?.contentHeightChanged(height) }
        relay.testEdge = { [weak self] edge in self?.showSidebar(edge) }
        panel.delegate = self
        panel.onDismiss = { [weak self] in self?.closeSettings() }

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: Self.symbolName, accessibilityDescription: "iEdge")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Keep the stored flag in step with what the system says (the user may have removed the
        // login item in System Settings).
        if !settings.isDemo, settings.settings.launchAtLogin != loginItem.isEnabled {
            settings.settings.launchAtLogin = loginItem.isEnabled
        }

        settings.$settings
            .map(\.paused)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] paused in
                MainActor.assumeIsolated { self?.updateIcon(paused: paused) }
            }
            .store(in: &cancellables)

        // Menus opened from inside the panel (the Atalhos list) must not count as clicking away.
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuDidBeginTracking(_:)),
            name: NSMenu.didBeginTrackingNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuDidEndTracking(_:)),
            name: NSMenu.didEndTrackingNotification, object: nil
        )
    }

    // MARK: Status item

    /// Paused: the icon is drawn dimmed, like a disabled menu-bar item.
    private func updateIcon(paused: Bool) {
        guard let button = statusItem.button else { return }
        button.appearsDisabled = paused
        button.toolTip = paused ? "iEdge (pausado)" : "iEdge"
    }

    // MARK: Settings panel

    func showSettings(tab: SettingsTab? = nil) {
        if let tab { navigation.tab = tab }
        navigation.dockEdge = SettingsDockSide.current()
        permissions.startWatching()
        loginItem.refresh()

        hostingView.layoutSubtreeIfNeeded()
        positionPanel()
        guard !panel.isVisible || panel.alphaValue < 1 else {
            panel.makeKey()
            return
        }
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        installClickMonitor()
    }

    func closeSettings(animated: Bool = true) {
        guard panel.isVisible else { return }
        removeClickMonitor()
        permissions.stopWatching()
        lastClosedAt = Date()
        // The app and folder choosers activate iEdge. Left active with no window, it would keep
        // the focus: the next ⌘V from the clipboard and the window capture would act on iEdge
        // instead of the app the user is working in.
        if NSApp.isActive { NSApp.deactivate() }
        guard animated else {
            panel.alphaValue = 0
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.panel.alphaValue == 0 else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    /// Glass rectangle of Settings when open, for `--frame-file`.
    func panelFramesForCapture() -> [String] {
        panel.isVisible ? [panel.glassFrameForCapture] : []
    }

    private func toggleSettings() {
        if panel.isVisible, panel.alphaValue > 0 {
            closeSettings()
        } else if Date().timeIntervalSince(lastClosedAt) > 0.25 {
            showSettings()
        }
    }

    private static func maxContentHeight() -> CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        // Header, tabs and separator take about 100 pt; leave room under the menu bar.
        return max(260, min(Theme.settingsMaxContentHeight, screenHeight - 160))
    }

    private func contentHeightChanged(_ height: CGFloat) {
        guard height > 0, abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        guard panel.isVisible else { return }
        var glass = panel.glassFrame
        let top = glass.maxY
        glass.size.height = ceil(height)
        glass.origin.y = top - glass.size.height
        panel.setGlassFrame(glass, display: true)
    }

    /// Under the icon, left-aligned with it like Control Center, kept inside the screen.
    private func positionPanel() {
        let width = Theme.settingsWidth
        let height = ceil(contentHeight)
        guard let button = statusItem.button, let buttonWindow = button.window else {
            panel.setGlassFrame(NSRect(x: 0, y: 0, width: width, height: height), display: false)
            return
        }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? anchor
        var x = anchor.minX
        x = min(x, visible.maxX - width - Self.screenMargin)
        x = max(x, visible.minX + Self.screenMargin)
        let top = min(anchor.minY, visible.maxY) - Self.gapBelowMenuBar
        panel.setGlassFrame(NSRect(x: x, y: top - height, width: width, height: height), display: false)
    }

    /// Clicks that land in other apps, the desktop or the menu bar close the panel.
    private func installClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeSettings() }
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Another app took focus (Cmd-Tab, System Settings…). Menus opened from the panel and the
        // open panels for apps and folders take key status for a moment; wait a beat and skip those.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.menuTracking, !SettingsOpenPanel.isPresenting, !self.panel.isKeyWindow else { return }
                self.closeSettings()
            }
        }
    }

    @objc private func menuDidBeginTracking(_ notification: Notification) {
        menuTracking = true
    }

    @objc private func menuDidEndTracking(_ notification: Notification) {
        menuTracking = false
    }

    // MARK: Clicks and menu

    @objc private func handleClick(_ sender: Any?) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showMenu()
            return
        }
        toggleSettings()
    }

    private func showMenu() {
        closeSettings()
        let menu = NSMenu()
        let paused = settings.settings.paused
        menu.addItem(item(paused ? "Retomar" : "Pausar", paused ? "play" : "pause", #selector(togglePause)))
        menu.addItem(.separator())
        menu.addItem(item("Mostrar barra esquerda", "sidebar.left", #selector(showLeft)))
        menu.addItem(item("Mostrar barra direita", "sidebar.right", #selector(showRight)))
        menu.addItem(.separator())
        menu.addItem(item("Ajustes…", "gearshape", #selector(openSettings), key: ","))
        menu.addItem(item("Sair do iEdge", nil, #selector(quit), key: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ symbol: String?, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }

    @objc private func togglePause() {
        settings.settings.paused.toggle()
    }

    @objc private func showLeft() { showSidebar(.left) }
    @objc private func showRight() { showSidebar(.right) }

    /// Opens the sidebar on `edge` of the main screen (or the screen Settings is on, for the
    /// "Testar" buttons), at mid height.
    private func showSidebar(_ edge: ScreenEdge) {
        let fromSettings = panel.isVisible
        guard let screen = (fromSettings ? panel.screen : nil) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        // The menu closes on mouse-up; open on the next turn so that click does not close the bar.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sidebar.show(edge: edge, on: screen, atY: screen.frame.midY)
                self.holdSidebarOpen()
            }
        }
    }

    /// Opened from the menu or "Testar", the cursor is far from the bar (on the menu bar or in
    /// Settings), and the bar closes 0.25 s after the cursor is more than 40 pt away: it would
    /// spring in and straight out. Keep it a few seconds, then let it follow the cursor again.
    private func holdSidebarOpen() {
        if holdTimer == nil {
            // `--pin` already keeps it open, for good.
            guard !sidebar.isPinned else { return }
            sidebar.isPinned = true
        }
        holdTimer?.invalidate()
        let timer = Timer(timeInterval: Self.sidebarHold, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseSidebarHold() }
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    private func releaseSidebarHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        sidebar.isPinned = false
    }

    @objc private func openSettings() {
        // The menu is still tracking on this turn; open once it has closed.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.showSettings() }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// Lets the SwiftUI root reach the controller that is still being initialised.
@MainActor private final class SettingsHeightRelay {
    var heightChanged: ((CGFloat) -> Void)?
    var testEdge: ((ScreenEdge) -> Void)?
}
