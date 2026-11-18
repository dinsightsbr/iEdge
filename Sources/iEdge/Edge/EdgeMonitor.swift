import AppKit

// Peça A: implementar a detecção (docs/SPEC.md §1.1): monitores global + local de mouseMoved,
// permanência `dwellMs` ou empurrão `pushDistance`, cantos, botão pressionado, Dock, pausa,
// borda real (EdgeGeometry) e rearme só depois de o cursor sair da borda. Sem timer contínuo.

/// Watches the cursor and calls `onTrigger` when it rests on, or pushes against, a real screen edge.
@MainActor final class EdgeMonitor {
    private let settings: SettingsStore
    private let isSidebarVisible: () -> Bool

    /// Edge, screen and the cursor's y (screen coordinates) at the moment of the trigger.
    var onTrigger: ((ScreenEdge, NSScreen, CGFloat) -> Void)?

    init(settings: SettingsStore, isSidebarVisible: @escaping () -> Bool) {
        self.settings = settings
        self.isSidebarVisible = isSidebarVisible
    }

    func start() {
        Log.edge.info("EdgeMonitor.start (ainda sem detecção)")
    }

    func stop() {}
}
