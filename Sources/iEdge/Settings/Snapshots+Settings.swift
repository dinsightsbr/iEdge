import SwiftUI

// One entry per tab, plus the shortcut form open. Permissions and the Dock side are fixed so the
// images do not depend on the machine that renders them.

extension SnapshotCatalog {
    @MainActor static var settings: [SnapshotEntry] {
        [
            settingsEntry("settings-itens", tab: .itens),
            settingsEntry("settings-itens-adicionar", tab: .itens) { navigation in
                var draft = SettingsItemDraft(kind: .link)
                draft.title = "Documentação"
                draft.link = "https://developer.apple.com/documentation"
                draft.symbol = "book"
                navigation.initialDraft = draft
            },
            settingsEntry("settings-bordas", tab: .bordas) { navigation in
                navigation.dockEdge = .left
            },
            settingsEntry("settings-capturas", tab: .capturas, screenCapture: false),
            settingsEntry("settings-clipboard", tab: .clipboard) { _ in },
            settingsEntry("settings-geral", tab: .geral, screenCapture: true, accessibility: false),
        ]
    }

    @MainActor private static func settingsEntry(
        _ name: String,
        tab: SettingsTab,
        screenCapture: Bool = true,
        accessibility: Bool = true,
        configure: @escaping @MainActor (SettingsNavigation) -> Void = { _ in }
    ) -> SnapshotEntry {
        SnapshotEntry(name: name, glassRadius: Theme.panelRadius) { context in
            let navigation = SettingsNavigation()
            navigation.tab = tab
            configure(navigation)
            prepareSnapshotSettings(context.settings, tab: tab)
            return AnyView(
                SettingsRootView(
                    settings: context.settings,
                    navigation: navigation,
                    clipboard: context.clipboard,
                    permissions: PermissionCenter(screenCapture: screenCapture, accessibility: accessibility),
                    loginItem: LoginItem(live: false, initiallyEnabled: true)
                )
            )
        }
    }

    /// Demo settings with a few custom shortcuts and values that show every state of the tab.
    @MainActor private static func prepareSnapshotSettings(_ store: SettingsStore, tab: SettingsTab) {
        var settings = store.settings
        settings.items += [
            SidebarItem(kind: .openApp(path: "/System/Applications/Notes.app"), title: "Notas"),
            SidebarItem(kind: .openURL("https://github.com"), title: "GitHub", symbol: "globe"),
            SidebarItem(kind: .shell(command: "open ~/Projetos"), title: "Projetos", symbol: "folder", enabled: false),
        ]
        settings.items[4].enabled = false
        if tab == .clipboard {
            settings.clipboard.autoPaste = true
        }
        store.settings = settings
    }
}
