import SwiftUI

// Peça A: acrescentar a barra com lupa (`sidebar-hover`), com rótulo e item selecionado.

extension SnapshotCatalog {
    @MainActor static var sidebar: [SnapshotEntry] {
        [
            SnapshotEntry(name: "sidebar", glassRadius: Theme.sidebarRadius) { context in
                AnyView(SidebarView(settings: context.settings, onTap: { _ in }))
            },
        ]
    }
}
