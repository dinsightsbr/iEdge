import Foundation

struct SidebarItem: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: ActionKind
    var title: String
    var symbol: String        // SF Symbol (ignored for openApp, which shows the app icon)
    var enabled: Bool
    var isBuiltIn: Bool

    init(id: UUID = UUID(), kind: ActionKind, title: String, symbol: String? = nil, enabled: Bool = true, isBuiltIn: Bool = false) {
        self.id = id
        self.kind = kind
        self.title = title
        self.symbol = symbol ?? kind.defaultSymbol
        self.enabled = enabled
        self.isBuiltIn = isBuiltIn
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, symbol, enabled, isBuiltIn
    }

    /// Only `kind` is required; everything else falls back to a sensible value.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(ActionKind.self, forKey: .kind)
        let symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            kind: kind,
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? kind.kindTitle,
            symbol: (symbol?.isEmpty ?? true) ? nil : symbol,
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            isBuiltIn: try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? kind.isBuiltInKind
        )
    }

    /// Built-in items, in their default order. Fixed ids keep them stable across "Restaurar padrão".
    static let defaults: [SidebarItem] = [
        builtIn(.screenshotFull, "Tela inteira", id: "1E0D6E00-0000-4000-8000-000000000001"),
        builtIn(.screenshotArea, "Área", id: "1E0D6E00-0000-4000-8000-000000000002"),
        builtIn(.screenshotWindow, "Janela", id: "1E0D6E00-0000-4000-8000-000000000003"),
        builtIn(.clipboard, "Área de transferência", id: "1E0D6E00-0000-4000-8000-000000000004"),
        builtIn(.captureTool, "Ferramenta de captura", id: "1E0D6E00-0000-4000-8000-000000000005"),
    ]

    static func defaultItem(for kind: ActionKind) -> SidebarItem? {
        defaults.first { $0.kind == kind }
    }

    private static func builtIn(_ kind: ActionKind, _ title: String, id: String) -> SidebarItem {
        SidebarItem(id: UUID(uuidString: id) ?? UUID(), kind: kind, title: title, isBuiltIn: true)
    }

    /// Repairs a decoded list: drops duplicate ids and built-in kinds, and appends any built-in that
    /// is missing (an older file, or a built-in added in a newer version).
    static func normalized(_ items: [SidebarItem]) -> [SidebarItem] {
        var seenIds = Set<UUID>()
        var seenBuiltIns = Set<ActionKind>()
        var result: [SidebarItem] = []
        for var item in items {
            guard !seenIds.contains(item.id) else { continue }
            if item.kind.isBuiltInKind {
                guard !seenBuiltIns.contains(item.kind) else { continue }
                seenBuiltIns.insert(item.kind)
                item.isBuiltIn = true
            } else {
                item.isBuiltIn = false
            }
            seenIds.insert(item.id)
            result.append(item)
        }
        for item in defaults where !seenBuiltIns.contains(item.kind) {
            var item = item
            if seenIds.contains(item.id) { item.id = UUID() }
            result.append(item)
        }
        return result
    }
}

/// Decodes an array skipping elements that fail (an unknown action type from a newer version).
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                _ = try? container.decode(Discard.self)
            }
        }
        self.elements = elements
    }

    private struct Discard: Decodable {}
}
