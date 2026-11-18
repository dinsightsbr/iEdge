import AppKit
import SwiftUI

// Peça C: painel de Ajustes completo (altura que abraça o conteúdo, fechar ao perder o foco sem
// fechar com menus abertos, como no iSessions), ícone refletindo a pausa.

/// Owns the menu-bar icon: left click toggles Settings in a glass panel under it, right click
/// shows the quick menu.
@MainActor final class StatusItemController: NSObject {
    private let settings: SettingsStore
    private let sidebar: SidebarController
    private let clipboard: ClipboardStore
    private let statusItem: NSStatusItem
    private let navigation = SettingsNavigation()
    private let panel: GlassPanel
    private let hostingView: NSHostingView<SettingsRootView>
    private var clickMonitor: Any?
    /// Clicking the icon while the panel is open closes it on mouse-down and would reopen it on
    /// mouse-up; remembering when it closed avoids the flicker.
    private var lastClosedAt: Date = .distantPast

    private static let gapBelowMenuBar: CGFloat = 6
    private static let screenMargin: CGFloat = 8

    init(settings: SettingsStore, sidebar: SidebarController, clipboard: ClipboardStore) {
        self.settings = settings
        self.sidebar = sidebar
        self.clipboard = clipboard
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let hosting = NSHostingView(rootView: SettingsRootView(settings: settings, navigation: navigation))
        hosting.sizingOptions = []
        self.hostingView = hosting
        self.panel = GlassPanel(content: hosting, configuration: .settings)
        super.init()

        panel.onDismiss = { [weak self] in self?.closeSettings() }
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "sidebar.squares.left", accessibilityDescription: "iEdge")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    // MARK: Settings panel

    func showSettings(tab: SettingsTab? = nil) {
        if let tab { navigation.tab = tab }
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        installClickMonitor()
    }

    func closeSettings() {
        guard panel.isVisible else { return }
        removeClickMonitor()
        lastClosedAt = Date()
        panel.orderOut(nil)
    }

    /// Glass rectangle of Settings when open, for `--frame-file`.
    func panelFramesForCapture() -> [String] {
        panel.isVisible ? [panel.glassFrameForCapture] : []
    }

    private func toggleSettings() {
        if panel.isVisible {
            closeSettings()
        } else if Date().timeIntervalSince(lastClosedAt) > 0.25 {
            showSettings()
        }
    }

    /// Under the icon, left-aligned with it like Control Center, kept inside the screen.
    private func positionPanel() {
        hostingView.layoutSubtreeIfNeeded()
        let width = Theme.settingsWidth
        let height = ceil(max(hostingView.fittingSize.height, 200))
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
        menu.addItem(item(settings.settings.paused ? "Retomar" : "Pausar", #selector(togglePause)))
        menu.addItem(.separator())
        menu.addItem(item("Mostrar barra esquerda", #selector(showLeft)))
        menu.addItem(item("Mostrar barra direita", #selector(showRight)))
        menu.addItem(.separator())
        menu.addItem(item("Ajustes…", #selector(openSettings), key: ","))
        menu.addItem(item("Sair do iEdge", #selector(quit), key: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func togglePause() {
        settings.settings.paused.toggle()
    }

    @objc private func showLeft() { showSidebar(.left) }
    @objc private func showRight() { showSidebar(.right) }

    private func showSidebar(_ edge: ScreenEdge) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        // The menu closes on mouse-up; open on the next turn so that click does not close the bar.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.sidebar.show(edge: edge, on: screen, atY: screen.frame.midY)
            }
        }
    }

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
