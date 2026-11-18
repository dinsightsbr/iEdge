import SwiftUI

// Peça B: acrescentar estados (vazio, hover, imagem grande, fixadas) conforme a lista evoluir.

extension SnapshotCatalog {
    @MainActor static var clipboard: [SnapshotEntry] {
        [
            SnapshotEntry(name: "clipboard", glassRadius: Theme.flyoutRadius) { context in
                AnyView(
                    ClipboardListView(store: context.clipboard, onPick: { _ in })
                        .frame(width: Theme.flyoutWidth)
                )
            },
        ]
    }
}
