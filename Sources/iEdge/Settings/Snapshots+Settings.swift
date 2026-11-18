import SwiftUI

// Peça C: uma entrada por aba (`settings-bordas`, `settings-capturas`, `settings-clipboard`,
// `settings-geral`) e estados relevantes (formulário de atalho aberto, permissão faltando).

extension SnapshotCatalog {
    @MainActor static var settings: [SnapshotEntry] {
        [
            SnapshotEntry(name: "settings-itens", glassRadius: Theme.panelRadius) { context in
                let navigation = SettingsNavigation()
                navigation.tab = .itens
                return AnyView(SettingsRootView(settings: context.settings, navigation: navigation))
            },
        ]
    }
}
