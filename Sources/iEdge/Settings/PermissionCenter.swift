import AppKit
import ApplicationServices
import CoreGraphics

/// Privacy permissions iEdge uses, as shown in Settings.
enum SettingsPermission: String, CaseIterable, Identifiable {
    /// Full-screen, area and window captures.
    case screenCapture
    /// Sending ⌘V after picking a clipboard entry ("Colar automaticamente").
    case accessibility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenCapture: return "Gravação de Tela"
        case .accessibility: return "Acessibilidade"
        }
    }

    var purpose: String {
        switch self {
        case .screenCapture: return "Capturas de tela, área e janela"
        case .accessibility: return "Colar ao escolher do clipboard"
        }
    }

    var symbol: String {
        switch self {
        case .screenCapture: return "rectangle.dashed.badge.record"
        case .accessibility: return "accessibility"
        }
    }

    /// Pane of System Settings › Privacy & Security that grants it.
    var settingsURL: URL? {
        switch self {
        case .screenCapture: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .accessibility: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }
}

/// Current state of the permissions, re-read while Settings is open: the user grants them in
/// System Settings and comes back, and nothing notifies the app of the change.
@MainActor final class PermissionCenter: ObservableObject {
    @Published private(set) var screenCapture: Bool
    @Published private(set) var accessibility: Bool

    /// nil reads the system; snapshots pass fixed values.
    private let fixed: (screenCapture: Bool, accessibility: Bool)?
    private var timer: Timer?

    static let pollInterval: TimeInterval = 1.5

    init() {
        fixed = nil
        screenCapture = CGPreflightScreenCaptureAccess()
        accessibility = AXIsProcessTrusted()
    }

    /// Fixed state that never touches the system (snapshots).
    init(screenCapture: Bool, accessibility: Bool) {
        fixed = (screenCapture, accessibility)
        self.screenCapture = screenCapture
        self.accessibility = accessibility
    }

    func isGranted(_ permission: SettingsPermission) -> Bool {
        switch permission {
        case .screenCapture: return screenCapture
        case .accessibility: return accessibility
        }
    }

    func refresh() {
        guard fixed == nil else { return }
        let screen = CGPreflightScreenCaptureAccess()
        let ax = AXIsProcessTrusted()
        if screen != screenCapture { screenCapture = screen }
        if ax != accessibility { accessibility = ax }
    }

    /// Permissions already asked for in this run: the system prompt shows only once, so the next
    /// request opens System Settings instead.
    @Published private(set) var asked: Set<SettingsPermission> = []

    /// First time: the system prompt (which has its own "Open System Settings" button). After
    /// that: the right pane of System Settings, since the prompt does not come back.
    func request(_ permission: SettingsPermission) {
        guard fixed == nil else { return }
        guard !asked.contains(permission) else {
            openSystemSettings(for: permission)
            return
        }
        asked.insert(permission)
        switch permission {
        case .screenCapture:
            _ = CGRequestScreenCaptureAccess()
        case .accessibility:
            // The literal value of kAXTrustedCheckOptionPrompt, which Swift 6 sees as shared
            // mutable state.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        refresh()
    }

    func openSystemSettings(for permission: SettingsPermission) {
        guard fixed == nil, let url = permission.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Polls while Settings is visible; `stopWatching` when it closes.
    func startWatching() {
        refresh()
        guard fixed == nil, timer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }
}
