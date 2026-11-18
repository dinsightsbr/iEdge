import Foundation

/// Pure edits of the sidebar item list made by the Itens tab. Kept free of UI so they can be tested.
///
/// Built-in items can be turned off and moved, never removed. Custom items can also be edited and
/// removed.
enum SettingsItemEditing {
    /// Moves the item with `id` so it ends up at `index` (clamped). Unknown ids leave the list as is.
    static func move(_ items: [SidebarItem], id: UUID, to index: Int) -> [SidebarItem] {
        guard let from = items.firstIndex(where: { $0.id == id }) else { return items }
        var result = items
        let item = result.remove(at: from)
        result.insert(item, at: min(max(index, 0), result.count))
        return result
    }

    /// Moves the item one step up (`offset` -1) or down (+1), as the ↑↓ buttons do.
    static func move(_ items: [SidebarItem], id: UUID, by offset: Int) -> [SidebarItem] {
        guard let from = items.firstIndex(where: { $0.id == id }) else { return items }
        return move(items, id: id, to: from + offset)
    }

    static func canMove(_ items: [SidebarItem], id: UUID, by offset: Int) -> Bool {
        guard let from = items.firstIndex(where: { $0.id == id }) else { return false }
        return items.indices.contains(from + offset)
    }

    /// Appends a new custom item (forced to be custom, with a fresh id if it collides).
    static func add(_ item: SidebarItem, to items: [SidebarItem]) -> [SidebarItem] {
        var item = item
        item.isBuiltIn = false
        if items.contains(where: { $0.id == item.id }) { item.id = UUID() }
        return items + [item]
    }

    /// Replaces the item with the same id, keeping its position. A built-in only takes the
    /// `enabled` flag: its kind, title and symbol are fixed.
    static func update(_ item: SidebarItem, in items: [SidebarItem]) -> [SidebarItem] {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return items }
        var result = items
        if result[index].isBuiltIn {
            result[index].enabled = item.enabled
        } else {
            var item = item
            item.isBuiltIn = false
            result[index] = item
        }
        return result
    }

    static func setEnabled(_ enabled: Bool, id: UUID, in items: [SidebarItem]) -> [SidebarItem] {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return items }
        var result = items
        result[index].enabled = enabled
        return result
    }

    /// Removes a custom item; built-ins stay.
    static func remove(id: UUID, from items: [SidebarItem]) -> [SidebarItem] {
        items.filter { $0.id != id || $0.isBuiltIn }
    }

    /// "Restaurar padrão": the built-ins come back in their default order and turned on, and the
    /// custom shortcuts are kept after them, turned off. Throwing them away would lose work the
    /// user cannot get back (paths, commands); off, they are one switch away and out of the bar.
    static func restoreDefaults(_ items: [SidebarItem]) -> [SidebarItem] {
        let custom = items.filter { !$0.isBuiltIn }.map { item -> SidebarItem in
            var item = item
            item.enabled = false
            return item
        }
        return SidebarItem.defaults + custom
    }

    /// True when "Restaurar padrão" would change something.
    static func differsFromDefaults(_ items: [SidebarItem]) -> Bool {
        restoreDefaults(items) != items
    }
}

/// The "Adicionar atalho" form: what the user typed, its validation and the item it makes.
struct SettingsItemDraft: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case app, link, shortcut, command

        var id: String { rawValue }

        var title: String {
            switch self {
            case .app: return "App"
            case .link: return "Link"
            case .shortcut: return "Atalho"
            case .command: return "Comando"
            }
        }

        var defaultSymbol: String {
            switch self {
            case .app: return ActionKind.openApp(path: "").defaultSymbol
            case .link: return ActionKind.openURL("").defaultSymbol
            case .shortcut: return ActionKind.shortcut(name: "").defaultSymbol
            case .command: return ActionKind.shell(command: "").defaultSymbol
            }
        }
    }

    enum Problem: Equatable {
        case emptyTitle, missingApp, invalidLink, emptyShortcut, emptyCommand, unknownSymbol

        var message: String {
            switch self {
            case .emptyTitle: return "Dê um nome ao atalho."
            case .missingApp: return "Escolha um app."
            case .invalidLink: return "Link inválido. Use um endereço (https://…) ou um caminho (/… ou ~/…)."
            case .emptyShortcut: return "Informe o nome do atalho do app Atalhos."
            case .emptyCommand: return "Informe o comando."
            case .unknownSymbol: return "Esse símbolo SF não existe."
            }
        }
    }

    var kind: Kind = .app
    var title = ""
    /// Empty uses the kind's default symbol.
    var symbol = ""
    var appPath = ""
    var link = ""
    var shortcutName = ""
    var command = ""

    init(kind: Kind = .app) {
        self.kind = kind
    }

    /// Prefills the form from a custom item being edited.
    init(item: SidebarItem) {
        title = item.title
        switch item.kind {
        case .openApp(let path):
            kind = .app
            appPath = path
        case .openURL(let url):
            kind = .link
            link = url
        case .shortcut(let name):
            kind = .shortcut
            shortcutName = name
        case .shell(let command):
            kind = .command
            self.command = command
        default:
            break
        }
        symbol = item.symbol == kind.defaultSymbol ? "" : item.symbol
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedSymbol: String { symbol.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Symbol shown in the preview and saved with the item.
    var effectiveSymbol: String { trimmedSymbol.isEmpty ? kind.defaultSymbol : trimmedSymbol }

    /// First problem in the form, or nil when it can be saved. `symbolExists` checks SF Symbols
    /// (injected so tests do not depend on the installed symbol set).
    func problem(symbolExists: (String) -> Bool) -> Problem? {
        if trimmedTitle.isEmpty { return .emptyTitle }
        switch kind {
        case .app:
            if appPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .missingApp }
        case .link:
            if Self.normalizedLink(link) == nil { return .invalidLink }
        case .shortcut:
            if shortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .emptyShortcut }
        case .command:
            if command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .emptyCommand }
        }
        if kind != .app, !trimmedSymbol.isEmpty, !symbolExists(trimmedSymbol) { return .unknownSymbol }
        return nil
    }

    var actionKind: ActionKind? {
        switch kind {
        case .app:
            let path = appPath.trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : .openApp(path: path)
        case .link:
            return Self.normalizedLink(link).map { .openURL($0) }
        case .shortcut:
            let name = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : .shortcut(name: name)
        case .command:
            let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
            return command.isEmpty ? nil : .shell(command: command)
        }
    }

    /// The item to save, or nil when the form is invalid. `existing` keeps the id and switch of
    /// an item being edited.
    func makeItem(existing: SidebarItem? = nil, symbolExists: (String) -> Bool) -> SidebarItem? {
        guard problem(symbolExists: symbolExists) == nil, let actionKind else { return nil }
        return SidebarItem(
            id: existing?.id ?? UUID(),
            kind: actionKind,
            title: trimmedTitle,
            symbol: effectiveSymbol,
            enabled: existing?.enabled ?? true,
            isBuiltIn: false
        )
    }

    /// What "Abrir link/arquivo" will open: a URL with a scheme (`https://…`, `mailto:…`), an
    /// absolute or `~` path (as `file://`), or a bare domain (`example.com` → `https://example.com`).
    /// nil when it is none of these.
    static func normalizedLink(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.hasPrefix("/") || text.hasPrefix("~") {
            let path = (text as NSString).expandingTildeInPath
            return URL(fileURLWithPath: path).absoluteString
        }
        guard !text.contains(where: \.isWhitespace) else { return nil }

        if let schemeEnd = text.range(of: ":"), text[..<schemeEnd.lowerBound].allSatisfy({ $0.isLetter || $0 == "+" || $0 == "-" || $0 == "." }),
           !text[..<schemeEnd.lowerBound].isEmpty,
           let url = URL(string: text), let scheme = url.scheme?.lowercased() {
            if scheme == "http" || scheme == "https" {
                guard let host = url.host, !host.isEmpty else { return nil }
            } else if text[schemeEnd.upperBound...].isEmpty {
                return nil
            }
            return text
        }

        // A bare domain: at least one dot with something on both sides.
        let host = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? text
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }), let url = URL(string: "https://" + text), url.host != nil else {
            return nil
        }
        return url.absoluteString
    }

    /// Display name of an app bundle ("Safari" for /Applications/Safari.app).
    static func appName(forPath path: String) -> String {
        let url = URL(fileURLWithPath: path)
        if let bundle = Bundle(url: url) {
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                if let name = bundle.localizedInfoDictionary?[key] as? String ?? bundle.infoDictionary?[key] as? String,
                   !name.isEmpty {
                    return name
                }
            }
        }
        return url.deletingPathExtension().lastPathComponent
    }
}

/// One-line state shown under "iEdge" in the Settings header ("Ativo nas duas bordas").
enum SettingsSummary {
    static func text(for settings: AppSettings, dockEdge: ScreenEdge?) -> (text: String, needsAttention: Bool) {
        if settings.paused { return ("Pausado", false) }
        let active = ScreenEdge.allCases.filter { edge in
            settings.isEdgeEnabled(edge) && (edge != dockEdge || settings.forceEdgeWithDock)
        }
        switch active.count {
        case 2: return ("Ativo nas duas bordas", false)
        case 1:
            let blockedByDock = dockEdge.map { settings.isEdgeEnabled($0) && !settings.forceEdgeWithDock } ?? false
            let name = active[0] == .left ? "esquerda" : "direita"
            return (blockedByDock ? "Ativo só na borda \(name) (Dock na outra)" : "Ativo na borda \(name)", false)
        default:
            if settings.edges.isEmpty { return ("Nenhuma borda ligada", true) }
            return ("Bordas bloqueadas pelo Dock", true)
        }
    }
}
