import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// "Itens": what the sidebar shows, in order. Built-ins can be turned off and moved; custom
/// shortcuts can also be edited and removed.
struct SettingsItemsView: View {
    @ObservedObject var settings: SettingsStore

    /// Form shown above the list: a new shortcut, or the custom item being edited.
    private enum Form: Equatable {
        case add
        case edit(SidebarItem)
    }

    @State private var form: Form?
    @State private var draft: SettingsItemDraft
    @State private var hovered: UUID?
    @State private var dragging: UUID?

    /// `startDraft` opens the form already filled (snapshots).
    init(settings: SettingsStore, startDraft: SettingsItemDraft? = nil) {
        self.settings = settings
        _form = State(initialValue: startDraft == nil ? nil : .add)
        _draft = State(initialValue: startDraft ?? SettingsItemDraft())
    }

    private var items: [SidebarItem] { settings.settings.items }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.settingsSectionSpacing) {
            if let form {
                SettingsItemForm(
                    draft: $draft,
                    editing: editingItem(form),
                    onCancel: closeForm,
                    onSave: save,
                    onRemove: removeEditing
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                HStack {
                    SettingsPillButton(title: "Adicionar atalho", symbol: "plus", style: .prominent) {
                        draft = SettingsItemDraft()
                        withAnimation(.snappy(duration: 0.2)) { form = .add }
                    }
                    Spacer()
                    Text("\(items.filter(\.enabled).count) de \(items.count) na barra")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Theme.contentInset - Theme.rowOutset)
            }

            SettingsSection(footer: "Arraste para reordenar (ou use ↑↓). Os itens embutidos podem ser desligados, não removidos.") {
                VStack(spacing: 2) {
                    ForEach(items) { item in
                        row(item)
                    }
                }
                .padding(-6)
            }

            HStack {
                SettingsConfirmButton(
                    title: "Restaurar padrão",
                    symbol: "arrow.counterclockwise",
                    question: "Voltar à ordem padrão? Seus atalhos ficam desligados no fim.",
                    confirmTitle: "Restaurar",
                    enabled: SettingsItemEditing.differsFromDefaults(items)
                ) {
                    withAnimation(.snappy(duration: 0.25)) {
                        settings.settings.items = SettingsItemEditing.restoreDefaults(items)
                    }
                    closeForm()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.contentInset - Theme.rowOutset)
        }
    }

    // MARK: Rows

    private func row(_ item: SidebarItem) -> some View {
        SettingsItemRow(
            item: item,
            hovering: hovered == item.id,
            canMoveUp: SettingsItemEditing.canMove(items, id: item.id, by: -1),
            canMoveDown: SettingsItemEditing.canMove(items, id: item.id, by: 1),
            isEditing: form.flatMap(editingItem)?.id == item.id,
            enabled: Binding(
                get: { item.enabled },
                set: { settings.settings.items = SettingsItemEditing.setEnabled($0, id: item.id, in: items) }
            ),
            onMove: { offset in
                withAnimation(.snappy(duration: 0.2)) {
                    settings.settings.items = SettingsItemEditing.move(items, id: item.id, by: offset)
                }
            },
            onEdit: {
                draft = SettingsItemDraft(item: item)
                withAnimation(.snappy(duration: 0.2)) { form = .edit(item) }
            }
        )
        .opacity(dragging == item.id ? 0.4 : 1)
        .onHover { inside in
            // Hover-in does not fire during a drag session, so it clears a drag that ended
            // outside any row (performDrop never ran). Hover-out may fire as the drag starts.
            if inside, dragging != nil { dragging = nil }
            if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
        }
        .modifier(ItemReorderModifier(item: item, dragging: $dragging) { id, target in
            guard let index = settings.settings.items.firstIndex(where: { $0.id == target }) else { return }
            withAnimation(.snappy(duration: 0.18)) {
                settings.settings.items = SettingsItemEditing.move(settings.settings.items, id: id, to: index)
            }
        })
    }

    // MARK: Form

    private func editingItem(_ form: Form) -> SidebarItem? {
        if case .edit(let item) = form { return item }
        return nil
    }

    private func closeForm() {
        withAnimation(.snappy(duration: 0.2)) { form = nil }
    }

    private func save() {
        // The stored copy, so a switch flipped while the form was open is kept.
        let existing = form.flatMap(editingItem).flatMap { editing in items.first { $0.id == editing.id } }
        guard let item = draft.makeItem(existing: existing, symbolExists: SettingsItemForm.symbolExists) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            if existing != nil {
                settings.settings.items = SettingsItemEditing.update(item, in: items)
            } else {
                settings.settings.items = SettingsItemEditing.add(item, to: items)
            }
            form = nil
        }
    }

    private func removeEditing() {
        guard let item = form.flatMap(editingItem) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            settings.settings.items = SettingsItemEditing.remove(id: item.id, from: items)
            form = nil
        }
    }
}

/// Drag to reorder. Left out of snapshots: ImageRenderer draws drag and drop sources as an
/// "unsupported" box.
private struct ItemReorderModifier: ViewModifier {
    let item: SidebarItem
    @Binding var dragging: UUID?
    let move: (UUID, UUID) -> Void
    @Environment(\.isSnapshot) private var isSnapshot

    func body(content: Content) -> some View {
        if isSnapshot {
            content
        } else {
            content
                .onDrag {
                    dragging = item.id
                    return NSItemProvider(object: item.id.uuidString as NSString)
                }
                .onDrop(of: [.text], delegate: ItemDropDelegate(target: item.id, dragging: $dragging, move: move))
        }
    }
}

/// Live reorder: the dragged row takes the place of the row it enters.
private struct ItemDropDelegate: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    let move: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        move(dragging, target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }
}

private struct SettingsItemRow: View {
    let item: SidebarItem
    let hovering: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let isEditing: Bool
    @Binding var enabled: Bool
    let onMove: (Int) -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .opacity(item.enabled ? 1 : 0.55)
            Spacer(minLength: 6)
            if hovering {
                HStack(spacing: 4) {
                    SettingsIconButton(symbol: "chevron.up", help: "Subir", enabled: canMoveUp) { onMove(-1) }
                    SettingsIconButton(symbol: "chevron.down", help: "Descer", enabled: canMoveDown) { onMove(1) }
                    if !item.isBuiltIn {
                        SettingsIconButton(symbol: "pencil", help: "Editar") { onEdit() }
                    }
                }
                .transition(.opacity)
            }
            Toggle(item.title, isOn: $enabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .snapshotStandIn { SnapshotControls.toggle(enabled) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius - 2, style: .continuous)
                .fill(isEditing ? Theme.selectedFill : (hovering ? Theme.hoverFill : .clear))
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder private var icon: some View {
        if case .openApp(let path) = item.kind {
            SettingsAppIcon(path: path)
        } else {
            SettingsSymbolTile(symbol: item.symbol)
        }
    }

    private var detail: String {
        if item.isBuiltIn { return "Embutido" }
        switch item.kind {
        case .openApp(let path): return "App · " + path.settingsAbbreviatedPath
        case .openURL(let url):
            if let fileURL = URL(string: url), fileURL.isFileURL { return "Arquivo · " + fileURL.path.settingsAbbreviatedPath }
            return "Link · " + url
        case .shortcut(let name): return "Atalho · " + name
        case .shell(let command): return "Comando · " + command
        default: return item.kind.kindTitle
        }
    }
}

/// Inline "Adicionar atalho" / "Editar atalho" form.
private struct SettingsItemForm: View {
    @Binding var draft: SettingsItemDraft
    let editing: SidebarItem?
    let onCancel: () -> Void
    let onSave: () -> Void
    let onRemove: () -> Void

    @State private var triedToSave = false
    @State private var shortcutNames: [String]?

    static func symbolExists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    private var problem: SettingsItemDraft.Problem? { draft.problem(symbolExists: Self.symbolExists) }

    var body: some View {
        SettingsSection(title: editing == nil ? "Novo atalho" : "Editar atalho") {
            SettingsSegmented(options: SettingsItemDraft.Kind.allCases, selection: $draft.kind) { $0.title }

            kindFields

            field("Nome") {
                SettingsTextField(placeholder: namePlaceholder, text: $draft.title)
            }

            if draft.kind != .app {
                field("Símbolo") {
                    HStack(spacing: 8) {
                        SettingsSymbolTile(
                            symbol: Self.symbolExists(draft.effectiveSymbol) ? draft.effectiveSymbol : "questionmark",
                            tint: Self.symbolExists(draft.effectiveSymbol) ? .primary : Theme.warning,
                            size: 24
                        )
                        SettingsTextField(placeholder: "Símbolo SF (padrão: \(draft.kind.defaultSymbol))", text: $draft.symbol, monospaced: true)
                    }
                }
            }

            if triedToSave, let problem {
                Label(problem.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if editing != nil {
                    SettingsConfirmButton(
                        title: "Remover",
                        symbol: "trash",
                        question: "Remover?",
                        confirmTitle: "Remover",
                        action: onRemove
                    )
                }
                Spacer(minLength: 0)
                SettingsPillButton(title: "Cancelar", action: onCancel)
                SettingsPillButton(title: editing == nil ? "Adicionar" : "Salvar", style: .prominent) {
                    triedToSave = true
                    if problem == nil { onSave() }
                }
            }
        }
        .onChange(of: draft.kind) { _, kind in
            triedToSave = false
            if kind == .shortcut { loadShortcutNames() }
        }
        .onAppear {
            if draft.kind == .shortcut { loadShortcutNames() }
        }
    }

    private var namePlaceholder: String {
        switch draft.kind {
        case .app: return "Nome (padrão: o do app)"
        case .link: return "Ex.: Documentação"
        case .shortcut: return "Ex.: Modo foco"
        case .command: return "Ex.: Abrir pasta de projetos"
        }
    }

    @ViewBuilder private var kindFields: some View {
        switch draft.kind {
        case .app:
            field("App") {
                HStack(spacing: 8) {
                    if draft.appPath.isEmpty {
                        SettingsSymbolTile(symbol: "app.dashed", tint: .secondary, size: 24)
                        Text("Nenhum app escolhido")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        SettingsAppIcon(path: draft.appPath, size: 24)
                        Text(draft.appPath.settingsAbbreviatedPath)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                    SettingsPillButton(title: "Escolher…", action: chooseApp)
                        .fixedSize()
                }
            }
        case .link:
            field("Link") {
                SettingsTextField(placeholder: "https://… ou ~/pasta/arquivo", text: $draft.link)
            }
        case .shortcut:
            field("Atalho") {
                HStack(spacing: 6) {
                    SettingsTextField(placeholder: "Nome no app Atalhos", text: $draft.shortcutName)
                    if let shortcutNames, !shortcutNames.isEmpty {
                        Menu {
                            ForEach(shortcutNames, id: \.self) { name in
                                Button(name) {
                                    if draft.title.isEmpty || draft.title == draft.shortcutName { draft.title = name }
                                    draft.shortcutName = name
                                }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Escolher entre os seus atalhos")
                        .snapshotStandIn { SettingsSymbolTile(symbol: "list.bullet", size: 22) }
                    }
                }
            }
        case .command:
            field("Comando") {
                SettingsTextField(placeholder: "open -a Terminal ~/Projetos", text: $draft.command, monospaced: true)
            }
            Text("Roda com /bin/zsh -lc, sem terminal. A saída é descartada.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            content()
        }
    }

    private func chooseApp() {
        guard let url = SettingsOpenPanel.chooseApp() else { return }
        let previousName = draft.appPath.isEmpty ? nil : SettingsItemDraft.appName(forPath: draft.appPath)
        draft.appPath = url.path
        if draft.trimmedTitle.isEmpty || draft.title == previousName {
            draft.title = SettingsItemDraft.appName(forPath: url.path)
        }
    }

    private func loadShortcutNames() {
        guard shortcutNames == nil else { return }
        Task {
            let names = await ShortcutsCatalog.names()
            shortcutNames = names
        }
    }
}

/// Names from `shortcuts list`, read off the main thread. Empty when the tool fails.
private enum ShortcutsCatalog {
    static func names() async -> [String] {
        await Task.detached(priority: .userInitiated) { () -> [String] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return []
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return [] }
            let names = text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }.value
    }
}
