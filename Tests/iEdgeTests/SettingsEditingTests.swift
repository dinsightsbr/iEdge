import XCTest
@testable import iEdge

final class SettingsEditingTests: XCTestCase {
    private let anySymbol: (String) -> Bool = { _ in true }
    private let noSymbol: (String) -> Bool = { _ in false }

    private func custom(_ title: String, _ kind: ActionKind, enabled: Bool = true) -> SidebarItem {
        SidebarItem(kind: kind, title: title, enabled: enabled)
    }

    private var sample: [SidebarItem] {
        SidebarItem.defaults + [
            custom("Safari", .openApp(path: "/Applications/Safari.app")),
            custom("Home", .shell(command: "open ~")),
        ]
    }

    // MARK: Move

    func testMoveToIndex() {
        let items = sample
        let moved = SettingsItemEditing.move(items, id: items[5].id, to: 0)
        XCTAssertEqual(moved.map(\.title).first, "Safari")
        XCTAssertEqual(moved.count, items.count)
        XCTAssertEqual(Set(moved.map(\.id)), Set(items.map(\.id)))
    }

    func testMoveClampsAndIgnoresUnknownIds() {
        let items = sample
        XCTAssertEqual(SettingsItemEditing.move(items, id: items[0].id, to: 99).last?.id, items[0].id)
        XCTAssertEqual(SettingsItemEditing.move(items, id: items[3].id, to: -4).first?.id, items[3].id)
        XCTAssertEqual(SettingsItemEditing.move(items, id: UUID(), to: 0), items)
    }

    func testMoveByOffset() {
        let items = sample
        let down = SettingsItemEditing.move(items, id: items[0].id, by: 1)
        XCTAssertEqual(down.map(\.id).prefix(2), [items[1].id, items[0].id])
        let up = SettingsItemEditing.move(items, id: items[6].id, by: -1)
        XCTAssertEqual(up[5].id, items[6].id)
        XCTAssertFalse(SettingsItemEditing.canMove(items, id: items[0].id, by: -1))
        XCTAssertFalse(SettingsItemEditing.canMove(items, id: items[6].id, by: 1))
        XCTAssertTrue(SettingsItemEditing.canMove(items, id: items[3].id, by: 1))
    }

    // MARK: Add, edit, remove

    func testAddMakesCustomItemWithFreshId() {
        let items = sample
        var duplicate = items[0]
        duplicate.title = "Cópia"
        let added = SettingsItemEditing.add(duplicate, to: items)
        XCTAssertEqual(added.count, items.count + 1)
        XCTAssertFalse(added.last?.isBuiltIn ?? true)
        XCTAssertNotEqual(added.last?.id, items[0].id)
    }

    func testUpdateCustomKeepsPosition() {
        let items = sample
        var edited = items[5]
        edited.title = "Navegador"
        edited.kind = .openApp(path: "/Applications/Firefox.app")
        let result = SettingsItemEditing.update(edited, in: items)
        XCTAssertEqual(result[5].title, "Navegador")
        XCTAssertEqual(result[5].kind, .openApp(path: "/Applications/Firefox.app"))
        XCTAssertEqual(result.count, items.count)
    }

    func testUpdateBuiltInOnlyChangesSwitch() {
        let items = sample
        var edited = items[0]
        edited.title = "Outro nome"
        edited.symbol = "star"
        edited.enabled = false
        let result = SettingsItemEditing.update(edited, in: items)
        XCTAssertEqual(result[0].title, items[0].title)
        XCTAssertEqual(result[0].symbol, items[0].symbol)
        XCTAssertFalse(result[0].enabled)
    }

    func testRemoveCustom() {
        let items = sample
        let result = SettingsItemEditing.remove(id: items[6].id, from: items)
        XCTAssertEqual(result.count, items.count - 1)
        XCTAssertFalse(result.contains { $0.id == items[6].id })
    }

    func testBuiltInIsNeverRemoved() {
        let items = sample
        for builtIn in SidebarItem.defaults {
            XCTAssertEqual(SettingsItemEditing.remove(id: builtIn.id, from: items), items)
        }
    }

    func testSetEnabled() {
        let items = sample
        let result = SettingsItemEditing.setEnabled(false, id: items[2].id, in: items)
        XCTAssertFalse(result[2].enabled)
        XCTAssertEqual(result.filter { !$0.enabled }.count, 1)
    }

    // MARK: Restore defaults

    func testRestoreDefaultsKeepsCustomItemsTurnedOff() {
        var items = SettingsItemEditing.move(sample, id: sample[5].id, to: 0)
        items = SettingsItemEditing.setEnabled(false, id: SidebarItem.defaults[1].id, in: items)
        let restored = SettingsItemEditing.restoreDefaults(items)

        XCTAssertEqual(Array(restored.prefix(SidebarItem.defaults.count)), SidebarItem.defaults)
        let custom = restored.dropFirst(SidebarItem.defaults.count)
        XCTAssertEqual(custom.map(\.title), ["Safari", "Home"])
        XCTAssertTrue(custom.allSatisfy { !$0.enabled && !$0.isBuiltIn })
        XCTAssertFalse(SettingsItemEditing.differsFromDefaults(restored))
        XCTAssertTrue(SettingsItemEditing.differsFromDefaults(items))
        XCTAssertFalse(SettingsItemEditing.differsFromDefaults(SidebarItem.defaults))
    }

    // MARK: Form validation

    func testEmptyTitle() {
        var draft = SettingsItemDraft(kind: .command)
        draft.command = "ls"
        draft.title = "   "
        XCTAssertEqual(draft.problem(symbolExists: anySymbol), .emptyTitle)
        XCTAssertNil(draft.makeItem(symbolExists: anySymbol))
    }

    func testAppNeedsPath() {
        var draft = SettingsItemDraft(kind: .app)
        draft.title = "Safari"
        XCTAssertEqual(draft.problem(symbolExists: anySymbol), .missingApp)
        draft.appPath = "/Applications/Safari.app"
        XCTAssertNil(draft.problem(symbolExists: anySymbol))
        XCTAssertEqual(draft.makeItem(symbolExists: anySymbol)?.kind, .openApp(path: "/Applications/Safari.app"))
    }

    func testEmptyCommandAndShortcut() {
        var command = SettingsItemDraft(kind: .command)
        command.title = "Home"
        command.command = "  \n"
        XCTAssertEqual(command.problem(symbolExists: anySymbol), .emptyCommand)

        var shortcut = SettingsItemDraft(kind: .shortcut)
        shortcut.title = "Foco"
        XCTAssertEqual(shortcut.problem(symbolExists: anySymbol), .emptyShortcut)
        shortcut.shortcutName = " Modo foco "
        XCTAssertEqual(shortcut.makeItem(symbolExists: anySymbol)?.kind, .shortcut(name: "Modo foco"))
    }

    func testInvalidLinks() {
        for text in ["", "   ", "não é link", "foo", "http://", "https://", ".com", "a..b", "mailto:"] {
            XCTAssertNil(SettingsItemDraft.normalizedLink(text), text)
            var draft = SettingsItemDraft(kind: .link)
            draft.title = "Site"
            draft.link = text
            XCTAssertEqual(draft.problem(symbolExists: anySymbol), .invalidLink, text)
        }
    }

    func testValidLinks() {
        XCTAssertEqual(SettingsItemDraft.normalizedLink("https://example.com/a?b=1"), "https://example.com/a?b=1")
        XCTAssertEqual(SettingsItemDraft.normalizedLink(" example.com "), "https://example.com")
        XCTAssertEqual(SettingsItemDraft.normalizedLink("example.com/docs"), "https://example.com/docs")
        XCTAssertEqual(SettingsItemDraft.normalizedLink("mailto:oi@example.com"), "mailto:oi@example.com")
        XCTAssertEqual(SettingsItemDraft.normalizedLink("/Users/Shared"), "file:///Users/Shared/")
        let home = SettingsItemDraft.normalizedLink("~/Documents")
        XCTAssertTrue(home?.hasPrefix("file:///") ?? false)
        XCTAssertFalse(home?.contains("~") ?? true)
    }

    func testSymbolDefaultsAndValidation() {
        var draft = SettingsItemDraft(kind: .command)
        draft.title = "Home"
        draft.command = "open ~"
        XCTAssertEqual(draft.makeItem(symbolExists: noSymbol)?.symbol, "terminal")
        draft.symbol = "nao.existe"
        XCTAssertEqual(draft.problem(symbolExists: noSymbol), .unknownSymbol)
        draft.symbol = "house"
        XCTAssertEqual(draft.makeItem(symbolExists: anySymbol)?.symbol, "house")
    }

    func testEditingKeepsIdAndSwitch() {
        let existing = custom("Home", .shell(command: "open ~"), enabled: false)
        var draft = SettingsItemDraft(item: existing)
        XCTAssertEqual(draft.kind, .command)
        XCTAssertEqual(draft.command, "open ~")
        XCTAssertEqual(draft.symbol, "", "default symbol is shown as empty")
        draft.title = "Início"
        let item = draft.makeItem(existing: existing, symbolExists: anySymbol)
        XCTAssertEqual(item?.id, existing.id)
        XCTAssertEqual(item?.enabled, false)
        XCTAssertEqual(item?.title, "Início")
    }

    // MARK: Header summary

    func testSummary() {
        var settings = AppSettings()
        XCTAssertEqual(SettingsSummary.text(for: settings, dockEdge: nil).text, "Ativo nas duas bordas")
        settings.edges = [.right]
        XCTAssertEqual(SettingsSummary.text(for: settings, dockEdge: nil).text, "Ativo na borda direita")
        settings.edges = [.left, .right]
        XCTAssertEqual(SettingsSummary.text(for: settings, dockEdge: .left).text, "Ativo só na borda direita (Dock na outra)")
        settings.forceEdgeWithDock = true
        XCTAssertEqual(SettingsSummary.text(for: settings, dockEdge: .left).text, "Ativo nas duas bordas")
        settings.edges = []
        XCTAssertTrue(SettingsSummary.text(for: settings, dockEdge: nil).needsAttention)
        settings.paused = true
        XCTAssertEqual(SettingsSummary.text(for: settings, dockEdge: nil).text, "Pausado")
    }
}
