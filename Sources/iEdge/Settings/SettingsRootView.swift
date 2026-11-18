import SwiftUI

// Peça C: uma view por aba (docs/SPEC.md §1.6), PermissionCenter, LoginItem, altura que abraça o
// conteúdo (como o PopoverRootView do iSessions). Hoje: segmented com as 5 abas vazias.

/// Which tab Settings shows; owned by the status item controller so `--settings` can pick it.
@MainActor final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .itens
}

/// Content of the Settings glass panel.
struct SettingsRootView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var navigation: SettingsNavigation

    static let contentHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("iEdge").font(.headline)
                Spacer()
                if settings.settings.paused {
                    Text("Pausado").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.contentInset)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Picker("Seção", selection: $navigation.tab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .snapshotStandIn {
                SnapshotControls.segmented(
                    SettingsTab.allCases.map(\.title),
                    selected: SettingsTab.allCases.firstIndex(of: navigation.tab) ?? 0
                )
            }
            .padding(.horizontal, Theme.contentInset - 2)
            .padding(.bottom, 10)

            Divider().padding(.horizontal, Theme.contentInset)

            CardView {
                Text("Aba \(navigation.tab.title): em construção")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
            .padding(Theme.rowOutset)
            .frame(height: Self.contentHeight, alignment: .top)
        }
        .frame(width: Theme.settingsWidth)
        .environment(\.locale, Locale(identifier: "pt_BR"))
    }
}
