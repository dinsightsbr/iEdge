import AppKit

/// Watches the cursor and calls `onTrigger` when it rests on, or pushes against, a real screen
/// edge (docs/SPEC.md §1.1).
///
/// Mouse events need no Accessibility permission. Nothing runs while the cursor is away from the
/// edges: the only timer is the dwell timer, scheduled when the cursor arrives on an edge and
/// cancelled as soon as it leaves or the edge fires.
@MainActor final class EdgeMonitor {
    private let settings: SettingsStore
    private let isSidebarVisible: () -> Bool

    /// Edge, screen and the cursor's y (screen coordinates) at the moment of the trigger.
    var onTrigger: ((ScreenEdge, NSScreen, CGFloat) -> Void)?

    private var monitors: [Any] = []
    private var state = EdgeTriggerState()
    private var dwellTimer: Timer?

    init(settings: SettingsStore, isSidebarVisible: @escaping () -> Bool) {
        self.settings = settings
        self.isSidebarVisible = isSidebarVisible
    }

    func start() {
        guard monitors.isEmpty else { return }
        // Dragged events only tell that a button is held (dragging a window, selecting text).
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let deltaX = event.deltaX
            let dragged = event.type != .mouseMoved
            MainActor.assumeIsolated { self?.handleMove(deltaX: deltaX, dragged: dragged) }
        }) {
            monitors.append(global)
        }
        // Our own panels (the sidebar, Settings) receive the events while the cursor is over them.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let deltaX = event.deltaX
            let dragged = event.type != .mouseMoved
            MainActor.assumeIsolated { self?.handleMove(deltaX: deltaX, dragged: dragged) }
            return event
        }) {
            monitors.append(local)
        }
        Log.edge.info("monitor de bordas ligado")
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        cancelDwellTimer()
        state.reset()
    }

    // MARK: Private

    private func handleMove(deltaX: CGFloat, dragged: Bool) {
        let current = settings.settings
        guard !current.paused else {
            state.reset()
            cancelDwellTimer()
            return
        }
        state.dwell = Double(current.dwellMs) / 1000
        state.pushDistance = current.pushDistance

        let point = NSEvent.mouseLocation
        let hit = currentHit(at: point, settings: current)
        if isSidebarVisible() {
            // Closing the sidebar must not reopen it until the cursor leaves the edge.
            state.latch(hit)
            cancelDwellTimer()
            return
        }

        let buttonDown = dragged || NSEvent.pressedMouseButtons != 0
        let fired = state.moved(hit: hit, deltaX: deltaX, buttonDown: buttonDown, time: Self.now)
        if let fired {
            cancelDwellTimer()
            trigger(fired, y: point.y)
        } else if state.armedHit != nil {
            if dwellTimer == nil { scheduleDwellTimer() }
        } else {
            cancelDwellTimer()
        }
    }

    private func currentHit(at point: NSPoint, settings: AppSettings) -> EdgeGeometry.Hit? {
        let screens = NSScreen.screens.map(\.frame)
        // Cheap test first: the Dock preference is read only when the cursor is on a side edge.
        guard let index = EdgeGeometry.screenIndex(containing: point, screens: screens),
              EdgeGeometry.touchedEdge(point, screen: screens[index]) != nil
        else { return nil }
        let config = EdgeGeometry.Config(
            edges: settings.edges,
            cornerExclusion: settings.cornerExclusion,
            dockEdge: settings.forceEdgeWithDock ? nil : EdgeDockSide.current(),
            forceEdgeWithDock: settings.forceEdgeWithDock
        )
        return EdgeGeometry.hit(at: point, screens: screens, config: config)
    }

    private func scheduleDwellTimer() {
        let timer = Timer(timeInterval: state.dwell, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dwellElapsed() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        dwellTimer = timer
    }

    private func dwellElapsed() {
        dwellTimer = nil
        guard !isSidebarVisible(), !settings.settings.paused, NSEvent.pressedMouseButtons == 0 else { return }
        let point = NSEvent.mouseLocation
        // The cursor may have left without a move event reaching us (e.g. a screen change).
        let hit = currentHit(at: point, settings: settings.settings)
        guard hit == state.armedHit else {
            state.latch(nil)
            return
        }
        if let fired = state.tick(time: Self.now) {
            trigger(fired, y: point.y)
        } else if state.armedHit != nil {
            // Fired early (timer leeway): wait for the rest.
            scheduleDwellTimer()
        }
    }

    private func cancelDwellTimer() {
        dwellTimer?.invalidate()
        dwellTimer = nil
    }

    private func trigger(_ hit: EdgeGeometry.Hit, y: CGFloat) {
        let screens = NSScreen.screens
        guard screens.indices.contains(hit.screenIndex) else { return }
        Log.edge.info("borda \(hit.edge.rawValue, privacy: .public) disparou")
        onTrigger?(hit.edge, screens[hit.screenIndex], y)
    }

    private static var now: Double { ProcessInfo.processInfo.systemUptime }
}
