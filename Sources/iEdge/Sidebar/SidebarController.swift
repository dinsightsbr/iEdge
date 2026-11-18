import AppKit
import Combine
import SwiftUI

/// Shows the sidebar on an edge, runs the magnifier while it is visible and runs the clicked item
/// (docs/SPEC.md §1.2–1.3).
@MainActor final class SidebarController {
    private let settings: SettingsStore
    private let clipboard: ClipboardStore
    private let actions: ActionPerforming

    private let model = SidebarModel()
    private var panels: [ScreenEdge: SidebarPanel] = [:]
    private var panel: SidebarPanel?
    private var flyout: ClipboardFlyout?
    private var clickMonitor: Any?
    private var displayLink: CADisplayLink?
    private lazy var ticker = SidebarTicker { [weak self] in self?.tick() }

    /// Bumped on every show and hide, so a finished exit animation does not hide a newer show.
    private var generation = 0
    private var isClosing = false
    private var selectedIndex: Int?
    /// When the cursor settled on the clipboard tile (the flyout opens after 250 ms).
    private var clipboardHoverStart: Double?
    /// When the cursor went more than 40 pt away from the glass (the sidebar closes after 250 ms).
    private var farSince: Double?
    /// Item count and tile size the open sidebar was laid out for.
    private var layoutKey: SidebarLayoutKey?
    private var settingsObserver: AnyCancellable?

    private(set) var edge: ScreenEdge = .left
    private(set) var screen: NSScreen?
    /// `--pin`: does not close by itself (click outside, cursor leaving).
    var isPinned = false
    /// `--hover`: simulated cursor at this fraction of the sidebar height (0 = top).
    private(set) var simulatedHover: Double?

    var isVisible: Bool { panel?.isVisible ?? false }

    static let selectionSlackInward: CGFloat = 24
    static let closeDistance: CGFloat = 40
    static let closeDelay: Double = 0.25
    static let flyoutHoverDelay: Double = 0.25

    init(settings: SettingsStore, clipboard: ClipboardStore, actions: ActionPerforming) {
        self.settings = settings
        self.clipboard = clipboard
        self.actions = actions
        // The view redraws with new settings at once; the window and the glass anchor must follow
        // when the items or their size change while the sidebar is open (pinned, or the Settings
        // "Testar" buttons). `$settings` publishes before the change, so the new value is passed on.
        settingsObserver = settings.$settings.sink { [weak self] new in
            MainActor.assumeIsolated { self?.settingsWillChange(to: new) }
        }
    }

    // MARK: Show and hide

    func show(edge: ScreenEdge, on screen: NSScreen, atY y: CGFloat) {
        if isVisible {
            if edge == self.edge, screen == self.screen, !isClosing { return }
            hide(animated: false)
        }
        generation += 1
        isClosing = false
        self.edge = edge
        self.screen = screen

        let panel = panel(for: edge)
        self.panel = panel
        let current = settings.settings
        let glass = glassRect(edge: edge, screen: screen, centerY: y, settings: current)
        panel.setGlassFrame(glass, display: false)
        layoutKey = SidebarLayoutKey(current)

        model.edge = edge
        model.canvas = SidebarCanvas(size: panel.frame.size, glassOrigin: panel.glassOriginInCanvas)
        let cursorY = simulatedCursorY(glass: glass) ?? (glass.maxY - y)
        model.cursorY = nil
        model.heldSelection = nil
        model.showsLabel = true
        model.cascadeOrigin = Magnification(
            count: current.enabledItems.count, tileSize: current.tileSize, magnification: 1, cursorY: cursorY,
            selectionSlack: .greatestFiniteMagnitude
        ).selectedIndex ?? 0
        model.animatesCascade = false
        model.presented = false
        selectedIndex = nil
        clipboardHoverStart = nil
        farSince = nil

        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.overlay.layoutSubtreeIfNeeded()
        if let view = panel.contentView {
            let margins = panel.margins
            let pivot = CGPoint(x: edge == .left ? margins.left : margins.left + glass.width, y: margins.bottom + glass.height / 2)
            let away = glass.width + Theme.sidebarEdgeGap
            SidebarAnimation.springIn(
                view, pivot: pivot, offset: CGVector(dx: edge == .left ? -away : away, dy: 0), scale: 0.92,
                damping: SidebarAnimation.damping(forOvershoot: SidebarAnimation.entryOvershoot, travel: away)
            )
        }
        // Next turn of the run loop, so the hidden state is drawn before the cascade starts.
        let token = generation
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                self.model.animatesCascade = true
                self.model.presented = true
            }
        }

        startDisplayLink(on: panel.overlay)
        installClickMonitor()
        tick()
        Log.sidebar.info("barra aberta na borda \(edge.rawValue, privacy: .public)")
    }

    func hide(animated: Bool) {
        hide(animated: animated, then: nil)
    }

    /// Closes the flyout and the sidebar; `then` runs once the sidebar is off screen.
    private func hide(animated: Bool, then completion: (@MainActor () -> Void)?) {
        if isClosing, animated {
            // Already on its way out: run after the exit instead of restarting it.
            if let completion {
                DispatchQueue.main.asyncAfter(deadline: .now() + SidebarAnimation.exitDuration) {
                    MainActor.assumeIsolated { completion() }
                }
            }
            return
        }
        hideFlyout()
        removeClickMonitor()
        stopDisplayLink()
        generation += 1
        guard let panel, panel.isVisible else {
            completion?()
            return
        }
        guard animated, let view = panel.contentView else {
            finishHide(panel)
            completion?()
            return
        }
        isClosing = true
        let glass = panel.glassFrame
        let margins = panel.margins
        let pivot = CGPoint(x: edge == .left ? margins.left : margins.left + glass.width, y: margins.bottom + glass.height / 2)
        let away = glass.width + Theme.sidebarEdgeGap
        let token = generation
        SidebarAnimation.out(view, pivot: pivot, offset: CGVector(dx: edge == .left ? -away : away, dy: 0), scale: 0.92) { [weak self] in
            guard let self else { return }
            // A newer show reuses the window: leave it alone.
            if self.generation == token {
                self.finishHide(panel)
            }
            completion?()
        }
    }

    private func finishHide(_ panel: SidebarPanel) {
        panel.orderOut(nil)
        if let view = panel.contentView { SidebarAnimation.reset(view) }
        isClosing = false
        model.cursorY = nil
        model.animatesCascade = false
        model.presented = false
    }

    func simulateHover(fraction: Double) {
        simulatedHover = min(max(fraction, 0), 1)
        tick()
    }

    // MARK: Flyout

    func showFlyout() {
        guard let panel, panel.isVisible, !isClosing, flyout == nil,
              let tile = tileRect(for: .clipboard)
        else { return }
        let flyout = ClipboardFlyout(store: clipboard, edge: edge) { [weak self] entry in self?.pick(entry) }
        flyout.panel.onDismiss = { [weak self] in self?.dismissIfNotPinned() }
        flyout.show(attachedTo: panel, sidebarGlass: panel.glassFrame, tile: tile, visibleFrame: screen?.visibleFrame)
        self.flyout = flyout
        // The flyout covers the inner side: the magnifier rests and the tile stays selected.
        model.heldSelection = settings.settings.enabledItems.firstIndex { $0.kind == .clipboard }
        model.showsLabel = false
    }

    func hideFlyout() {
        guard let flyout else { return }
        flyout.close()
        self.flyout = nil
        model.heldSelection = nil
        model.showsLabel = true
        clipboardHoverStart = nil
    }

    // MARK: Development

    /// On-screen rectangles of the open panels, for `--frame-file`: the sidebar's glass with the
    /// magnified tiles and the label that spill past it, and the flyout's glass.
    func panelFramesForCapture() -> [String] {
        var lines: [String] = []
        if let panel, panel.isVisible {
            lines.append(GlassPanel.captureString(for: sidebarDrawnRect(panel: panel).integral))
        }
        if let flyout, flyout.panel.isVisible {
            lines.append(flyout.panel.glassFrameForCapture)
        }
        return lines
    }

    // MARK: Display link

    private func startDisplayLink(on view: NSView) {
        stopDisplayLink()
        let link = view.displayLink(target: ticker, selector: #selector(SidebarTicker.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Every frame while visible: magnifier, selection, haptics, the flyout's hover delay and
    /// closing when the cursor goes away.
    private func tick() {
        guard let panel, panel.isVisible, !isClosing else { return }
        let glass = panel.glassFrame
        let mouse = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        let current = settings.settings
        let overFlyout = flyout?.glassFrame.insetBy(dx: -4, dy: -4).contains(mouse) ?? false

        var cursorY: CGFloat?
        if let simulated = simulatedCursorY(glass: glass) {
            cursorY = simulated
        } else if !overFlyout, isInSelectionBand(mouse, glass: glass) {
            cursorY = glass.maxY - mouse.y
        }

        var magnifierY = cursorY
        let layout = SidebarView.layout(settings: current, cursorY: cursorY)
        if flyout != nil, let index = layout.selectedIndex, current.enabledItems[index].kind == .clipboard {
            // Back on the clipboard tile with the flyout open: keep resting under the flyout.
            magnifierY = nil
        }
        if Self.changed(model.cursorY, magnifierY) {
            model.cursorY = magnifierY
        }

        updateSelection(layout.selectedIndex, items: current.enabledItems, now: now, haptics: current.haptics)

        guard !isPinned, simulatedHover == nil else {
            farSince = nil
            return
        }
        var distance = Self.distance(from: mouse, to: sidebarDrawnRect(panel: panel))
        if let flyout { distance = min(distance, Self.distance(from: mouse, to: flyout.glassFrame)) }
        if distance > Self.closeDistance {
            if let farSince {
                if now - farSince >= Self.closeDelay { dismissIfNotPinned() }
            } else {
                farSince = now
            }
        } else {
            farSince = nil
        }
    }

    private func updateSelection(_ index: Int?, items: [SidebarItem], now: Double, haptics: Bool) {
        if index != selectedIndex {
            if index != nil, haptics {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            selectedIndex = index
            clipboardHoverStart = nil
            if let index, flyout != nil, items[index].kind != .clipboard {
                hideFlyout()
            }
        }
        guard let index, items.indices.contains(index), items[index].kind == .clipboard, flyout == nil else { return }
        if let start = clipboardHoverStart {
            if now - start >= Self.flyoutHoverDelay { showFlyout() }
        } else {
            clipboardHoverStart = now
        }
    }

    /// Between the screen edge and `selectionSlackInward` past the capsule's inner side.
    private func isInSelectionBand(_ point: CGPoint, glass: CGRect) -> Bool {
        let screenFrame = screen?.frame ?? glass
        switch edge {
        case .left: return point.x >= screenFrame.minX - 1 && point.x <= glass.maxX + Self.selectionSlackInward
        case .right: return point.x <= screenFrame.maxX + 1 && point.x >= glass.minX - Self.selectionSlackInward
        }
    }

    private func simulatedCursorY(glass: CGRect) -> CGFloat? {
        simulatedHover.map { CGFloat($0) * glass.height }
    }

    /// Skips sub-quarter-point changes, so a still cursor does not redraw the tiles every frame.
    private static func changed(_ old: CGFloat?, _ new: CGFloat?) -> Bool {
        switch (old, new) {
        case (nil, nil): return false
        case let (old?, new?): return abs(old - new) > 0.25
        default: return true
        }
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: Clicks

    private func handleMouseDown() {
        tick()
        let items = settings.settings.enabledItems
        guard let index = selectedIndex ?? model.heldSelection, items.indices.contains(index) else { return }
        handleTap(items[index])
    }

    private func handleTap(_ item: SidebarItem) {
        if item.kind == .clipboard {
            if flyout == nil { showFlyout() } else { hideFlyout() }
            return
        }
        guard let screen else { return }
        let context = ActionContext(edge: edge, screen: screen, anchor: tileRect(for: item.id) ?? panel?.glassFrame ?? .zero)
        Log.sidebar.info("executando item \(item.title, privacy: .public)")
        // Close first (animated), run after: captures must not include the sidebar.
        let actions = actions
        hide(animated: true) {
            actions.perform(item, context: context)
        }
    }

    private func pick(_ entry: ClipboardEntry) {
        let paste = settings.settings.clipboard.autoPaste
        let clipboard = clipboard
        hide(animated: true) {
            clipboard.copy(entry, paste: paste)
        }
    }

    private func dismissIfNotPinned() {
        guard !isPinned else { return }
        hide(animated: true)
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

    // MARK: Geometry

    private func panel(for edge: ScreenEdge) -> SidebarPanel {
        if let panel = panels[edge] { return panel }
        let overlay = SidebarOverlayView(rootView: SidebarView(settings: settings, model: model))
        let panel = SidebarPanel(edge: edge, overlay: overlay)
        panel.onDismiss = { [weak self] in self?.dismissIfNotPinned() }
        overlay.isInteractive = { [weak self, weak panel] point in
            guard let self, let panel else { return false }
            return self.isInteractive(point, in: panel)
        }
        overlay.onMouseDown = { [weak self] _ in self?.handleMouseDown() }
        panels[edge] = panel
        return panel
    }

    /// Whether a point in the overlay (window coordinates) is on the capsule or a magnified tile.
    private func isInteractive(_ point: NSPoint, in panel: SidebarPanel) -> Bool {
        guard panel.isVisible, !isClosing else { return false }
        let screenPoint = NSPoint(x: point.x + panel.frame.minX, y: point.y + panel.frame.minY)
        if SidebarView.capsuleRect(currentLayout(), glass: panel.glassFrame).contains(screenPoint) { return true }
        return currentTileRects(panel: panel).contains { $0.contains(screenPoint) }
    }

    private func currentLayout() -> Magnification {
        SidebarView.layout(settings: settings.settings, cursorY: model.cursorY)
    }

    private func currentTileRects(panel: SidebarPanel) -> [CGRect] {
        let tileSize = settings.settings.tileSize
        return currentLayout().tiles.map { SidebarView.tileRect($0, glass: panel.glassFrame, tileSize: tileSize, edge: edge) }
    }

    /// The capsule (grown with the magnifier) with the magnified tiles and the label, in screen
    /// coordinates.
    private func sidebarDrawnRect(panel: SidebarPanel) -> CGRect {
        let layout = currentLayout()
        let tileSize = settings.settings.tileSize
        let tiles = layout.tiles.map { SidebarView.tileRect($0, glass: panel.glassFrame, tileSize: tileSize, edge: edge) }
        var rect = tiles.reduce(SidebarView.capsuleRect(layout, glass: panel.glassFrame)) { $0.union($1) }
        let items = settings.settings.enabledItems
        if settings.settings.showLabels, model.showsLabel,
           let index = layout.selectedIndex, items.indices.contains(index), tiles.indices.contains(index) {
            let tile = tiles[index]
            let textWidth = (items[index].title as NSString).size(withAttributes: [.font: Theme.sidebarLabelFont]).width
            let width = min(ceil(textWidth) + 20, Theme.sidebarLabelMaxWidth)
            let x = edge == .left ? tile.maxX + Theme.sidebarLabelGap : tile.minX - Theme.sidebarLabelGap - width
            rect = rect.union(CGRect(x: x, y: tile.midY - Theme.sidebarLabelHeight / 2, width: width, height: Theme.sidebarLabelHeight))
        }
        return rect
    }

    /// Re-lays the open sidebar out around the same centre when the items or the tile size change.
    private func settingsWillChange(to new: AppSettings) {
        let key = SidebarLayoutKey(new)
        guard key != layoutKey, let panel, let screen, panel.isVisible, !isClosing else { return }
        layoutKey = key
        hideFlyout()
        selectedIndex = nil
        clipboardHoverStart = nil
        let glass = glassRect(edge: edge, screen: screen, centerY: panel.glassFrame.midY, settings: new)
        panel.setGlassFrame(glass, display: false)
        model.canvas = SidebarCanvas(size: panel.frame.size, glassOrigin: panel.glassOriginInCanvas)
        model.cascadeOrigin = min(model.cascadeOrigin, max(new.enabledItems.count - 1, 0))
    }

    private func glassRect(edge: ScreenEdge, screen: NSScreen, centerY: CGFloat, settings: AppSettings) -> CGRect {
        let size = SidebarView.glassSize(itemCount: settings.enabledItems.count, tileSize: settings.tileSize)
        let frame = screen.frame
        let visible = screen.visibleFrame
        let x = edge == .left ? frame.minX + Theme.sidebarEdgeGap : frame.maxX - Theme.sidebarEdgeGap - size.width
        let minY = visible.minY + Theme.sidebarEdgeGap
        let maxY = max(minY, visible.maxY - Theme.sidebarEdgeGap - size.height)
        let y = min(max(centerY - size.height / 2, minY), maxY)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// On-screen rectangle (at rest) of the first enabled tile of `kind`.
    private func tileRect(for kind: ActionKind) -> CGRect? {
        guard let index = settings.settings.enabledItems.firstIndex(where: { $0.kind == kind }) else { return nil }
        return tileRect(index: index)
    }

    private func tileRect(for id: UUID) -> CGRect? {
        guard let index = settings.settings.enabledItems.firstIndex(where: { $0.id == id }) else { return nil }
        return tileRect(index: index)
    }

    private func tileRect(index: Int) -> CGRect? {
        guard let panel else { return nil }
        return SidebarView.tileRect(index: index, glass: panel.glassFrame, tileSize: settings.settings.tileSize)
    }
}

/// What the sidebar window's size depends on.
struct SidebarLayoutKey: Equatable {
    var itemCount: Int
    var tileSize: Double

    init(_ settings: AppSettings) {
        itemCount = settings.enabledItems.count
        tileSize = settings.tileSize
    }
}

/// Display-link target (needs an Objective-C selector); holds the controller weakly through
/// its closure, so the link does not keep the controller alive.
private final class SidebarTicker: NSObject {
    private let onTick: @MainActor () -> Void

    init(onTick: @escaping @MainActor () -> Void) {
        self.onTick = onTick
    }

    @objc func tick(_ link: CADisplayLink) {
        MainActor.assumeIsolated { onTick() }
    }
}
