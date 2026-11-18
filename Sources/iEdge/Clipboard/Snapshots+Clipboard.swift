import SwiftUI

extension SnapshotCatalog {
    @MainActor static var clipboard: [SnapshotEntry] {
        [
            SnapshotEntry(name: "clipboard", glassRadius: Theme.flyoutRadius) { context in
                // Hover the third row, as if the cursor rested on it.
                let hovered = context.clipboard.sortedEntries.dropFirst(2).first?.id
                return AnyView(
                    ClipboardListView(store: context.clipboard, onPick: { _ in }, hover: ClipboardHoverModel(hoveredID: hovered))
                        .frame(width: Theme.flyoutWidth)
                )
            },
            SnapshotEntry(name: "clipboard-empty", glassRadius: Theme.flyoutRadius) { context in
                AnyView(
                    ClipboardListView(store: ClipboardStore(settings: context.settings, previewEntries: []), onPick: { _ in })
                        .frame(width: Theme.flyoutWidth)
                )
            },
            SnapshotEntry(name: "capture-toast", glassRadius: Theme.toastRadius) { _ in
                AnyView(CaptureToastView(content: .capture(image: CaptureToastPreview.screenshot(), fileName: "Captura de Tela 2026-11-18 às 14.05.33.png")))
            },
            SnapshotEntry(name: "error-toast", glassRadius: Theme.toastRadius) { _ in
                AnyView(CaptureToastView(content: .message(
                    symbol: "exclamationmark.triangle.fill",
                    title: "Comando falhou",
                    detail: "deploy.sh: permissão negada (código 126)",
                    actionTitle: nil
                )))
            },
            SnapshotEntry(name: "permission-toast", glassRadius: Theme.toastRadius) { _ in
                AnyView(CaptureToastView(content: .message(
                    symbol: "rectangle.dashed.badge.record",
                    title: "Permitir Gravação de Tela",
                    detail: "O iEdge precisa dessa permissão para capturar a tela.",
                    actionTitle: "Abrir Ajustes do Sistema"
                )))
            },
        ]
    }
}

/// Drawn stand-ins for the toast snapshots.
@MainActor enum CaptureToastPreview {
    /// A fake desktop: wallpaper gradient with two windows.
    static func screenshot() -> NSImage {
        NSImage(size: NSSize(width: 480, height: 300), flipped: false) { rect in
            NSGradient(colors: [.systemIndigo, .systemPurple, .systemOrange])?.draw(in: rect, angle: 30)
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: NSRect(x: 40, y: 60, width: 250, height: 180), xRadius: 12, yRadius: 12).fill()
            NSColor.black.withAlphaComponent(0.75).setFill()
            NSBezierPath(roundedRect: NSRect(x: 230, y: 30, width: 210, height: 140), xRadius: 12, yRadius: 12).fill()
            NSColor.systemBlue.setFill()
            NSBezierPath(roundedRect: NSRect(x: 60, y: 200, width: 90, height: 14), xRadius: 4, yRadius: 4).fill()
            return true
        }
    }
}
