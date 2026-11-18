import AppKit
import ServiceManagement

/// "Abrir ao iniciar sessão", on top of `SMAppService.mainApp`. The system only accepts the app
/// when it runs as a bundle, and it behaves reliably only from /Applications, so anything else
/// shows a message instead of failing silently.
@MainActor final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled: Bool
    /// Last failure, shown under the switch.
    @Published private(set) var message: String?
    /// Registered, but the user turned it off in System Settings › Login Items.
    @Published private(set) var needsApproval = false

    private let live: Bool

    /// live: false keeps everything in memory (demo and snapshots).
    init(live: Bool, initiallyEnabled: Bool = false) {
        self.live = live
        isEnabled = initiallyEnabled
        refresh()
    }

    func refresh() {
        guard live else { return }
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    /// Returns the state actually reached, so the caller can mirror it in `AppSettings`.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        message = nil
        guard live else {
            isEnabled = enabled
            return enabled
        }
        if enabled, let problem = Self.locationProblem() {
            message = problem
            refresh()
            return isEnabled
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            message = "Não deu para \(enabled ? "ligar" : "desligar"): \(error.localizedDescription)"
            Log.settings.error("SMAppService: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
        return isEnabled
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Why the running copy cannot be a login item, or nil.
    private static func locationProblem() -> String? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app" else {
            return "Só funciona com o iEdge.app (gere com scripts/build-app.sh) instalado em /Applications."
        }
        let path = url.resolvingSymlinksInPath().path
        guard path.hasPrefix("/Applications/") else {
            return "Mova o iEdge.app para a pasta Aplicativos (/Applications) e tente de novo."
        }
        return nil
    }
}
