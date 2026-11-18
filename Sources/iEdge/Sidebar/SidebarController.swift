import AppKit
import SwiftUI

// Peça A: salto com mola ao abrir e saída ease-in ao fechar, display link da lupa só com a barra
// visível (usar `simulatedHover` quando definido), seleção pelo cursor com folga, háptico,
// fechar ao afastar 40 pt (250 ms de tolerância), flyout que abre após 250 ms parado no tile e
// salta do tile (ClipboardFlyout). Hoje: abre/fecha seco, fecha com clique fora.

/// Shows the sidebar on an edge and runs the clicked item.
@MainActor final class SidebarController {
    private let settings: SettingsStore
    private let clipboard: ClipboardStore
    private let actions: ActionPerforming

    private let panel: SidebarPanel
    private var flyout: GlassPanel?
    private var clickMonitor: Any?

    private(set) var edge: ScreenEdge = .left
    private(set) var screen: NSScreen?
    /// `--pin`: does not close by itself (click outside, cursor leaving).
    var isPinned = false
    /// `--hover`: simulated cursor at this fraction of the sidebar height (0 = top).
    private(set) var simulatedHover: Double?

    var isVisible: Bool { panel.isVisible }

    init(settings: SettingsStore, clipboard: ClipboardStore, actions: ActionPerforming) {
        self.settings = settings
        self.clipboard = clipboard
        self.actions = actions

        var tap: (SidebarItem) -> Void = { _ in }
        let hosting = FirstMouseHostingView(rootView: SidebarView(settings: settings, onTap: { tap($0) }))
        hosting.sizingOptions = []
        self.panel = SidebarPanel(content: hosting)
        tap = { [weak self] item in self?.handleTap(item) }
        panel.onDismiss = { [weak self] in self?.dismissIfNotPinned() }
    }

    func show(edge: ScreenEdge, on screen: NSScreen, atY y: CGFloat) {
        self.edge = edge
        self.screen = screen
        let glass = glassRect(edge: edge, screen: screen, centerY: y)
        panel.setGlassFrame(glass, display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        installClickMonitor()
        Log.sidebar.info("barra aberta na borda \(edge.rawValue, privacy: .public)")
    }

    func hide(animated: Bool) {
        hideFlyout()
        removeClickMonitor()
        guard panel.isVisible else { return }
        guard animated else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.panel.alphaValue == 0 else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    func simulateHover(fraction: Double) {
        simulatedHover = fraction
    }

    // MARK: Flyout

    func showFlyout() {
        guard panel.isVisible, flyout == nil else { return }
        let list = ClipboardListView(store: clipboard) { [weak self] entry in self?.pick(entry) }
            .frame(width: Theme.flyoutWidth)
        let hosting = FirstMouseHostingView(rootView: list)
        let height = ceil(hosting.fittingSize.height)
        hosting.sizingOptions = []
        let flyout = GlassPanel(content: hosting, configuration: SidebarPanel.flyoutConfiguration)
        flyout.onDismiss = { [weak self] in self?.dismissIfNotPinned() }

        let sidebarGlass = panel.glassFrame
        let anchor = tileRect(for: .clipboard) ?? sidebarGlass
        let x = edge == .left
            ? sidebarGlass.maxX + Theme.sidebarEdgeGap
            : sidebarGlass.minX - Theme.sidebarEdgeGap - Theme.flyoutWidth
        var glass = CGRect(x: x, y: anchor.maxY - height, width: Theme.flyoutWidth, height: height)
        if let visible = screen?.visibleFrame {
            glass.origin.y = min(max(glass.minY, visible.minY + Theme.sidebarEdgeGap), visible.maxY - height - Theme.sidebarEdgeGap)
        }
        flyout.setGlassFrame(glass, display: false)
        panel.addChildWindow(flyout, ordered: .above)
        flyout.orderFrontRegardless()
        self.flyout = flyout
    }

    func hideFlyout() {
        guard let flyout else { return }
        panel.removeChildWindow(flyout)
        flyout.orderOut(nil)
        self.flyout = nil
    }

    // MARK: Development

    /// Glass rectangles of the open panels, for `--frame-file`.
    func panelFramesForCapture() -> [String] {
        [panel, flyout].compactMap { $0 }.filter(\.isVisible).map(\.glassFrameForCapture)
    }

    // MARK: Private

    private func handleTap(_ item: SidebarItem) {
        if item.kind == .clipboard {
            if flyout == nil { showFlyout() } else { hideFlyout() }
            return
        }
        guard let screen else { return }
        let context = ActionContext(edge: edge, screen: screen, anchor: tileRect(for: item.kind) ?? panel.glassFrame)
        // Close first: captures must not include the sidebar.
        hide(animated: false)
        actions.perform(item, context: context)
    }

    private func pick(_ entry: ClipboardEntry) {
        let paste = settings.settings.clipboard.autoPaste
        hide(animated: true)
        clipboard.copy(entry, paste: paste)
    }

    private func dismissIfNotPinned() {
        guard !isPinned else { return }
        hide(animated: true)
    }

    private func glassRect(edge: ScreenEdge, screen: NSScreen, centerY: CGFloat) -> CGRect {
        let size = SidebarView.glassSize(itemCount: settings.settings.enabledItems.count, tileSize: settings.settings.tileSize)
        let frame = screen.frame
        let visible = screen.visibleFrame
        let x = edge == .left ? frame.minX + Theme.sidebarEdgeGap : frame.maxX - Theme.sidebarEdgeGap - size.width
        let minY = visible.minY + Theme.sidebarEdgeGap
        let maxY = max(minY, visible.maxY - Theme.sidebarEdgeGap - size.height)
        let y = min(max(centerY - size.height / 2, minY), maxY)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// On-screen rectangle of the first enabled tile of `kind`.
    private func tileRect(for kind: ActionKind) -> CGRect? {
        guard let index = settings.settings.enabledItems.firstIndex(where: { $0.kind == kind }) else { return nil }
        return SidebarView.tileRect(index: index, glass: panel.glassFrame, tileSize: settings.settings.tileSize)
    }

    /// Clicks in other apps close the sidebar (clicks on its own margin arrive via `onDismiss`).
    private func installClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissIfNotPinned() }
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }
}
