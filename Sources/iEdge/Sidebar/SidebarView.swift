import AppKit
import SwiftUI

// Peça A: lupa (Magnification, função pura) com tiles crescendo para dentro da tela e empurrando
// os vizinhos, item selecionado em accentColor + rótulo em cápsula de vidro, entrada em cascata
// com mola, execução no mouseDown. Hoje: tiles fixos num VStack, clique via Button.

/// Tiles of the sidebar, laid out top to bottom inside the glass capsule.
struct SidebarView: View {
    @ObservedObject var settings: SettingsStore
    /// Tile currently selected (hover); drawn with the accent fill.
    var selectedID: UUID?
    var onTap: (SidebarItem) -> Void

    var body: some View {
        let tileSize = settings.settings.tileSize
        VStack(spacing: Theme.tileSpacing) {
            ForEach(settings.settings.enabledItems) { item in
                Button { onTap(item) } label: {
                    SidebarTile(item: item, size: tileSize, selected: item.id == selectedID)
                }
                .buttonStyle(.plain)
                .help(item.title)
                .accessibilityLabel(item.title)
            }
        }
        .padding(Theme.sidebarPadding)
        .fixedSize()
    }

    // MARK: Layout (shared with the controller, which positions the window and the anchors)

    static func glassSize(itemCount: Int, tileSize: CGFloat) -> CGSize {
        let count = CGFloat(max(itemCount, 1))
        return CGSize(
            width: tileSize + 2 * Theme.sidebarPadding,
            height: count * tileSize + (count - 1) * Theme.tileSpacing + 2 * Theme.sidebarPadding
        )
    }

    /// Rectangle of tile `index` (0 = top) for a glass rectangle in screen coordinates (y up).
    static func tileRect(index: Int, glass: CGRect, tileSize: CGFloat) -> CGRect {
        let top = glass.maxY - Theme.sidebarPadding - CGFloat(index) * (tileSize + Theme.tileSpacing)
        return CGRect(x: glass.minX + Theme.sidebarPadding, y: top - tileSize, width: tileSize, height: tileSize)
    }
}

struct SidebarTile: View {
    let item: SidebarItem
    let size: CGFloat
    var selected = false

    var body: some View {
        ZStack {
            Circle().fill(selected ? Theme.accent : Theme.tileFill)
            icon
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }

    @ViewBuilder
    private var icon: some View {
        if case .openApp(let path) = item.kind {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: size * 0.68, height: size * 0.68)
        } else {
            Image(systemName: item.symbol)
                .font(.system(size: Theme.tileSymbolSize, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
    }
}
