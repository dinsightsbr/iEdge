import AppKit
import SwiftUI

// Peça B: linha completa (docs/SPEC.md §1.3): hover com faixa e ampliação 1.0 → 1.04 com mola,
// botão de fixar no hover, até 10 visíveis com rolagem, estado vazio. A largura (300) e o vidro
// são do flyout (peça A); esta view só desenha o conteúdo.

/// Clipboard history list, embedded by the sidebar's flyout.
struct ClipboardListView: View {
    @ObservedObject var store: ClipboardStore
    var onPick: (ClipboardEntry) -> Void

    static let rowHeight: CGFloat = 52
    static let maxVisibleRows = 10

    private var sortedEntries: [ClipboardEntry] {
        store.entries.filter(\.pinned) + store.entries.filter { !$0.pinned }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Theme.contentInset)
                .padding(.top, 12)
                .padding(.bottom, 8)
            Divider().padding(.horizontal, Theme.contentInset)
            LiveScrollView {
                VStack(spacing: 2) {
                    ForEach(sortedEntries) { entry in
                        ClipboardRow(entry: entry, image: store.image(for: entry))
                            .contentShape(Rectangle())
                            .onTapGesture { onPick(entry) }
                    }
                }
                .padding(.horizontal, Theme.rowOutset)
                .padding(.vertical, 6)
            }
            .frame(height: min(CGFloat(max(sortedEntries.count, 1)), CGFloat(Self.maxVisibleRows)) * (Self.rowHeight + 2) + 12)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Área de transferência")
                .font(.headline)
            Text("\(store.entries.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            let canClear = !store.entries.allSatisfy(\.pinned)
            Button("Limpar") { store.clear() }
                .buttonStyle(.borderless)
                .disabled(!canClear)
                .snapshotStandIn { SnapshotControls.plainButton("Limpar", enabled: canClear) }
        }
    }
}

private struct ClipboardRow: View {
    let entry: ClipboardEntry
    let image: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.summary)
                    .font(.callout)
                    .lineLimit(2)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    if let icon = sourceIcon {
                        Image(nsImage: icon).resizable().frame(width: 12, height: 12)
                    }
                    Text(RelativeTime.string(from: entry.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if entry.pinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: ClipboardListView.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var leading: some View {
        switch entry.content {
        case .image:
            Group {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .files(let paths):
            Image(nsImage: NSWorkspace.shared.icon(forFile: paths.first ?? "/"))
                .resizable()
                .frame(width: 28, height: 28)
        case .url:
            Image(systemName: "link").frame(width: 28)
        case .text:
            EmptyView()
        }
    }

    private var sourceIcon: NSImage? {
        guard let bundleID = entry.sourceBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// "agora", "há 2 min", "há 3 h", "há 2 d".
enum RelativeTime {
    static func string(from date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "agora" }
        if seconds < 3600 { return "há \(Int(seconds / 60)) min" }
        if seconds < 86_400 { return "há \(Int(seconds / 3600)) h" }
        return "há \(Int(seconds / 86_400)) d"
    }
}
