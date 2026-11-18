import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Which row is under the cursor. The list feeds it from SwiftUI hover; the flyout can also drive
/// it from `NSEvent.mouseLocation` with `hover(at:)` if hover events do not reach its non-key
/// panel. Row frames are in the list's coordinate space (origin top-left of the view).
@MainActor final class ClipboardHoverModel: ObservableObject {
    @Published var hoveredID: UUID?
    /// Frames of the visible rows, reported by the list.
    fileprivate(set) var rowFrames: [UUID: CGRect] = [:]

    init(hoveredID: UUID? = nil) {
        self.hoveredID = hoveredID
    }

    /// Highlights the row at `point` (list coordinates, top-left origin); nil clears it.
    func hover(at point: CGPoint?) {
        let id = point.flatMap { point in rowFrames.first { $0.value.contains(point) }?.key }
        if id != hoveredID { hoveredID = id }
    }
}

/// Clipboard history list, embedded by the sidebar's flyout (which sets the width and the glass).
struct ClipboardListView: View {
    @ObservedObject var store: ClipboardStore
    var onPick: (ClipboardEntry) -> Void
    /// Optional external hover source (see `ClipboardHoverModel`); the list keeps its own otherwise.
    var hover: ClipboardHoverModel? = nil

    static let rowHeight: CGFloat = 52
    static let rowSpacing: CGFloat = 2
    static let maxVisibleRows = 10

    @StateObject private var ownHover = ClipboardHoverModel()

    var body: some View {
        ClipboardListContent(store: store, hover: hover ?? ownHover, onPick: onPick)
    }
}

private struct ClipboardListContent: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var hover: ClipboardHoverModel
    var onPick: (ClipboardEntry) -> Void

    private static let space = "clipboardList"

    var body: some View {
        let entries = store.sortedEntries
        VStack(spacing: 0) {
            header(count: entries.count)
                .padding(.horizontal, Theme.contentInset)
                .padding(.top, 14)
                .padding(.bottom, 10)
            if entries.isEmpty {
                emptyState
            } else {
                LiveScrollView {
                    VStack(spacing: ClipboardListView.rowSpacing) {
                        ForEach(entries) { entry in
                            row(entry)
                        }
                    }
                    .padding(.horizontal, Theme.rowOutset)
                    .padding(.bottom, Theme.rowOutset)
                }
                .frame(height: listHeight(count: entries.count))
            }
        }
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(ClipboardRowFramesKey.self) { frames in
            MainActor.assumeIsolated { hover.rowFrames = frames }
        }
    }

    private func listHeight(count: Int) -> CGFloat {
        let rows = CGFloat(min(count, ClipboardListView.maxVisibleRows))
        return rows * ClipboardListView.rowHeight + max(0, rows - 1) * ClipboardListView.rowSpacing + Theme.rowOutset
    }

    private func row(_ entry: ClipboardEntry) -> some View {
        let isHovered = hover.hoveredID == entry.id
        return ClipboardRow(
            entry: entry,
            image: store.image(for: entry),
            isHovered: isHovered,
            onTogglePin: { store.togglePin(entry) }
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ClipboardRowFramesKey.self, value: [entry.id: proxy.frame(in: .named(Self.space))])
            }
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
        .onContinuousHover { phase in
            switch phase {
            case .active: if hover.hoveredID != entry.id { hover.hoveredID = entry.id }
            case .ended: if hover.hoveredID == entry.id { hover.hoveredID = nil }
            }
        }
        .onTapGesture { onPick(entry) }
        .contextMenu {
            Button(entry.pinned ? "Desafixar" : "Fixar") { store.togglePin(entry) }
            Button("Remover") { store.remove(entry) }
        }
        .zIndex(isHovered ? 1 : 0)
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Área de transferência")
                .font(.headline)
            if count > 0 {
                Text("\(count)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            let canClear = store.entries.contains { !$0.pinned }
            Button("Limpar") { store.clear() }
                .buttonStyle(.borderless)
                .disabled(!canClear)
                .snapshotStandIn { SnapshotControls.plainButton("Limpar", enabled: canClear) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            Text("Nada copiado ainda")
                .font(.headline)
            Text("O que você copiar aparece aqui.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 30)
        .padding(.horizontal, Theme.contentInset)
    }
}

private struct ClipboardRowFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct ClipboardRow: View {
    let entry: ClipboardEntry
    let image: NSImage?
    let isHovered: Bool
    let onTogglePin: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            leading
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout)
                    .lineLimit(isText ? 2 : 1)
                    .truncationMode(isText ? .tail : .middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    if let icon = ClipboardSourceIcon.icon(for: entry.sourceBundleID) {
                        Image(nsImage: icon).resizable().interpolation(.high).frame(width: 12, height: 12)
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            pinControl
        }
        .padding(.leading, isText ? 10 : 6)
        .padding(.trailing, 6)
        .frame(height: ClipboardListView.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(isHovered ? Theme.hoverFill : Color.clear)
        )
        .scaleEffect(isHovered ? 1.04 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isHovered)
    }

    private var isText: Bool {
        if case .text = entry.content { return true }
        return false
    }

    private var title: String {
        switch entry.content {
        case .text(let text):
            // Collapse blank lines so two lines of preview show two lines of text.
            return text
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        case .url(let url):
            return url.replacingOccurrences(of: #"^https?://(www\.)?"#, with: "", options: .regularExpression)
        case .image:
            return "Imagem"
        default:
            return entry.summary
        }
    }

    private var subtitle: String {
        let time = RelativeTime.string(from: entry.date)
        switch entry.content {
        case let .image(_, _, width, height, _) where width > 0:
            return "\(Int(width)) × \(Int(height)) · \(time)"
        case .files(let paths) where paths.count > 1:
            let first = (paths[0] as NSString).lastPathComponent
            return "\(first) e mais \(paths.count - 1) · \(time)"
        case .url:
            return "Link · \(time)"
        default:
            return time
        }
    }

    @ViewBuilder
    private var pinControl: some View {
        if isHovered || entry.pinned {
            Button(action: onTogglePin) {
                Image(systemName: entry.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(entry.pinned ? Theme.accent : Color.secondary)
                    .rotationEffect(.degrees(45))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(isHovered ? Theme.tileFill : Color.clear))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(entry.pinned ? "Desafixar" : "Fixar")
        }
    }

    @ViewBuilder
    private var leading: some View {
        switch entry.content {
        case .image:
            Group {
                if let image {
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 40)
            .background(Theme.tileFill)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        case .files(let paths):
            ClipboardFileIcon(path: paths.first ?? "/")
                .frame(width: 40, height: 40)
        case .url:
            Image(systemName: "link")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.tileFill))
        case .text:
            EmptyView()
        }
    }
}

/// Icon of a file, or of its type when the file no longer exists.
private struct ClipboardFileIcon: View {
    let path: String

    var body: some View {
        Image(nsImage: icon).resizable().interpolation(.high).frame(width: 34, height: 34)
    }

    private var icon: NSImage {
        if FileManager.default.fileExists(atPath: path) { return NSWorkspace.shared.icon(forFile: path) }
        let ext = (path as NSString).pathExtension
        if let type = UTType(filenameExtension: ext) { return NSWorkspace.shared.icon(for: type) }
        return NSWorkspace.shared.icon(for: .data)
    }
}

/// App icons by bundle id, looked up once (Launch Services is slow enough to stutter a list).
@MainActor private enum ClipboardSourceIcon {
    private static var cache: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID, !missing.contains(bundleID) else { return nil }
        if let icon = cache[bundleID] { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            missing.insert(bundleID)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}

/// "agora", "há 2 min", "há 3 h", "ontem", "há 2 d".
enum RelativeTime {
    static func string(from date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "agora" }
        if seconds < 3600 { return "há \(Int(seconds / 60)) min" }
        if seconds < 86_400 { return "há \(Int(seconds / 3600)) h" }
        let days = Int(seconds / 86_400)
        return days == 1 ? "ontem" : "há \(days) d"
    }
}
