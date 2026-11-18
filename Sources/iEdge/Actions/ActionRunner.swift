import AppKit

// Peça B: executar de verdade (docs/SPEC.md §1.4 e §1.5): capturas via ScreenshotService
// (screencapture com argumentos em array, destino, som, permissão, prévia CaptureToast),
// Ferramenta de captura, e os atalhos personalizados em CustomActions (abrir app, link/arquivo,
// app Atalhos, comando). Falha vira aviso curto, nunca alerta modal.

/// Runs sidebar items. The sidebar is already closed when `perform` is called.
@MainActor final class ActionRunner: ActionPerforming {
    private let settings: SettingsStore
    private let clipboard: ClipboardStore

    init(settings: SettingsStore, clipboard: ClipboardStore) {
        self.settings = settings
        self.clipboard = clipboard
    }

    func perform(_ item: SidebarItem, context: ActionContext) {
        Log.actions.info("perform \(item.title, privacy: .public) [\(item.kind.kindTitle, privacy: .public)] na borda \(context.edge.rawValue, privacy: .public) (ainda não executa)")
    }
}
