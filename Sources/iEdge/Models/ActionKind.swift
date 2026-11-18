import Foundation

/// What a sidebar item does when clicked.
///
/// Encoded as a flat object with a `type` discriminator (`{"type":"openURL","url":"…"}`) instead of
/// the synthesized `{"openURL":{"_0":"…"}}`, so settings.json stays readable and an unknown type
/// from a newer version fails only that item, not the whole file.
enum ActionKind: Codable, Hashable {
    case screenshotFull, screenshotArea, screenshotWindow, captureTool, clipboard
    case openApp(path: String)
    case openURL(String)
    case shortcut(name: String)
    case shell(command: String)

    /// Kinds that ship with the app; they can be turned off but not removed.
    static let builtIns: [ActionKind] = [.screenshotFull, .screenshotArea, .screenshotWindow, .clipboard, .captureTool]

    var isBuiltInKind: Bool { Self.builtIns.contains(self) }

    var isScreenshot: Bool {
        switch self {
        case .screenshotFull, .screenshotArea, .screenshotWindow: return true
        default: return false
        }
    }

    /// SF Symbol used when an item does not name its own (openApp shows the app icon instead).
    var defaultSymbol: String {
        switch self {
        case .screenshotFull: return "display"
        case .screenshotArea: return "rectangle.dashed"
        case .screenshotWindow: return "macwindow"
        case .captureTool: return "record.circle"
        case .clipboard: return "doc.on.clipboard"
        case .openApp: return "app"
        case .openURL: return "link"
        case .shortcut: return "square.2.layers.3d"
        case .shell: return "terminal"
        }
    }

    /// Name of the kind as shown in Settings ("Adicionar atalho").
    var kindTitle: String {
        switch self {
        case .screenshotFull: return "Tela inteira"
        case .screenshotArea: return "Área"
        case .screenshotWindow: return "Janela"
        case .captureTool: return "Ferramenta de captura"
        case .clipboard: return "Área de transferência"
        case .openApp: return "Abrir app"
        case .openURL: return "Abrir link/arquivo"
        case .shortcut: return "Atalho"
        case .shell: return "Comando"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, path, url, name, command
    }

    private enum KindType: String, Codable {
        case screenshotFull, screenshotArea, screenshotWindow, captureTool, clipboard
        case openApp, openURL, shortcut, shell
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(KindType.self, forKey: .type) {
        case .screenshotFull: self = .screenshotFull
        case .screenshotArea: self = .screenshotArea
        case .screenshotWindow: self = .screenshotWindow
        case .captureTool: self = .captureTool
        case .clipboard: self = .clipboard
        case .openApp: self = .openApp(path: try container.decode(String.self, forKey: .path))
        case .openURL: self = .openURL(try container.decode(String.self, forKey: .url))
        case .shortcut: self = .shortcut(name: try container.decode(String.self, forKey: .name))
        case .shell: self = .shell(command: try container.decode(String.self, forKey: .command))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .screenshotFull: try container.encode(KindType.screenshotFull, forKey: .type)
        case .screenshotArea: try container.encode(KindType.screenshotArea, forKey: .type)
        case .screenshotWindow: try container.encode(KindType.screenshotWindow, forKey: .type)
        case .captureTool: try container.encode(KindType.captureTool, forKey: .type)
        case .clipboard: try container.encode(KindType.clipboard, forKey: .type)
        case .openApp(let path):
            try container.encode(KindType.openApp, forKey: .type)
            try container.encode(path, forKey: .path)
        case .openURL(let url):
            try container.encode(KindType.openURL, forKey: .type)
            try container.encode(url, forKey: .url)
        case .shortcut(let name):
            try container.encode(KindType.shortcut, forKey: .type)
            try container.encode(name, forKey: .name)
        case .shell(let command):
            try container.encode(KindType.shell, forKey: .type)
            try container.encode(command, forKey: .command)
        }
    }
}
