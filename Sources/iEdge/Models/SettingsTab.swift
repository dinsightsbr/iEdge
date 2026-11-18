import Foundation

/// Tabs of the Settings panel. Raw values are the names accepted by `--settings`.
enum SettingsTab: String, CaseIterable, Identifiable {
    case itens, bordas, capturas, clipboard, geral

    var id: String { rawValue }

    var title: String {
        switch self {
        case .itens: return "Itens"
        case .bordas: return "Bordas"
        case .capturas: return "Capturas"
        case .clipboard: return "Clipboard"
        case .geral: return "Geral"
        }
    }
}
