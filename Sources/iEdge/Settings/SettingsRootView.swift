import SwiftUI

/// Which tab Settings shows, plus what the controller refreshes each time it opens.
@MainActor final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .itens
    /// Side the Dock is on, re-read when Settings opens.
    @Published var dockEdge: ScreenEdge?
    /// Opens the Itens tab with the shortcut form already filled (snapshots).
    var initialDraft: SettingsItemDraft?
}

/// Content of the Settings glass panel: header with the overall state, the five tabs and the
/// current tab. It reports its height so the panel can hug it, like a Control Center module.
struct SettingsRootView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var permissions: PermissionCenter
    @ObservedObject var loginItem: LoginItem
    var maxContentHeight: CGFloat = Theme.settingsMaxContentHeight
    var onTestEdge: (ScreenEdge) -> Void = { _ in }
    var onQuit: () -> Void = { NSApp.terminate(nil) }
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @State private var contentHeight: CGFloat = 0
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Theme.contentInset)
                .padding(.top, 14)
                .padding(.bottom, 10)

            SettingsSegmented(options: SettingsTab.allCases, selection: $navigation.tab) { $0.title }
                .padding(.horizontal, Theme.contentInset - 2)
                .padding(.bottom, 10)

            Divider().padding(.horizontal, Theme.contentInset)

            LiveScrollView {
                content
                    .padding(.horizontal, Theme.rowOutset)
                    .padding(.top, 10)
                    .padding(.bottom, Theme.rowOutset)
                    .background(SettingsHeightReader<SettingsContentHeightKey>())
            }
            .frame(height: isSnapshot ? nil : min(max(contentHeight, 44), maxContentHeight))
            .onPreferenceChange(SettingsContentHeightKey.self) { height in
                MainActor.assumeIsolated { contentHeight = height }
            }
        }
        .frame(width: Theme.settingsWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(SettingsHeightReader<SettingsRootHeightKey>())
        .onPreferenceChange(SettingsRootHeightKey.self) { height in
            MainActor.assumeIsolated { onHeightChange(height) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.locale, Locale(identifier: "pt_BR"))
    }

    private var header: some View {
        let summary = SettingsSummary.text(for: settings.settings, dockEdge: navigation.dockEdge)
        let paused = settings.settings.paused
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("iEdge")
                    .font(.system(size: 13, weight: .semibold))
                Text(summary.text)
                    .font(.system(size: 11))
                    .foregroundStyle(summary.needsAttention ? Theme.warning : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                settings.settings.paused.toggle()
            } label: {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(paused ? Color.white : Color.primary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(paused ? Theme.accent : Color.primary.opacity(0.07)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(paused ? "Retomar" : "Pausar")
        }
    }

    @ViewBuilder private var content: some View {
        switch navigation.tab {
        case .itens:
            SettingsItemsView(settings: settings, startDraft: navigation.initialDraft)
        case .bordas:
            SettingsEdgesView(settings: settings, dockEdge: navigation.dockEdge, onTest: onTestEdge)
        case .capturas:
            SettingsCapturesView(settings: settings, permissions: permissions)
        case .clipboard:
            SettingsClipboardView(settings: settings, clipboard: clipboard, permissions: permissions)
        case .geral:
            SettingsGeneralView(settings: settings, permissions: permissions, loginItem: loginItem, onQuit: onQuit)
        }
    }
}

private struct SettingsContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct SettingsRootHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct SettingsHeightReader<Key: PreferenceKey>: View where Key.Value == CGFloat {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: Key.self, value: proxy.size.height)
        }
    }
}
