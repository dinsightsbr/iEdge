import AppKit
import SwiftUI

/// "Clipboard": history, automatic paste and the apps whose copies are never recorded.
struct SettingsClipboardView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var permissions: PermissionCenter

    private var clip: ClipboardSettings { settings.settings.clipboard }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.settingsSectionSpacing) {
            SettingsSection(title: "Histórico") {
                SettingsToggleRow(
                    title: "Guardar o histórico",
                    detail: "Mantém as entradas depois de sair do iEdge",
                    isOn: $settings.settings.clipboard.persist
                )
                SettingsSliderRow(
                    title: "Tamanho",
                    value: Binding(
                        get: { Double(clip.maxEntries) },
                        set: { settings.settings.clipboard.maxEntries = Int($0.rounded()) }
                    ),
                    range: Double(ClipboardSettings.maxEntriesRange.lowerBound)...Double(ClipboardSettings.maxEntriesRange.upperBound),
                    step: 10
                ) { "\(Int($0)) itens" }
            }

            SettingsSection(title: "Colar") {
                SettingsToggleRow(
                    title: "Colar automaticamente",
                    detail: "Ao escolher uma entrada, cola no app da frente (⌘V)",
                    isOn: Binding(
                        get: { clip.autoPaste },
                        set: { on in
                            settings.settings.clipboard.autoPaste = on
                            if on, !permissions.accessibility { permissions.request(.accessibility) }
                        }
                    )
                )
                if clip.autoPaste {
                    SettingsPermissionRow(permission: .accessibility, center: permissions)
                }
            }

            SettingsSection(
                title: "Apps excluídos",
                footer: "Cópias feitas nesses apps não entram no histórico. Conteúdo marcado como senha nunca entra."
            ) {
                VStack(spacing: 6) {
                    ForEach(clip.excludedBundleIDs, id: \.self) { bundleID in
                        ExcludedAppRow(bundleID: bundleID) {
                            settings.settings.clipboard.excludedBundleIDs.removeAll { $0 == bundleID }
                        }
                    }
                    if clip.excludedBundleIDs.isEmpty {
                        Text("Nenhum app excluído")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                HStack {
                    SettingsPillButton(title: "Adicionar app…", symbol: "plus", action: addApp)
                    Spacer(minLength: 0)
                }
            }

            HStack {
                SettingsConfirmButton(
                    title: "Limpar histórico",
                    symbol: "trash",
                    question: "Apagar as \(unpinnedCount) entradas não fixadas?",
                    confirmTitle: "Limpar",
                    enabled: unpinnedCount > 0
                ) {
                    clipboard.clear()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.contentInset - Theme.rowOutset)
        }
    }

    private var unpinnedCount: Int { clipboard.entries.filter { !$0.pinned }.count }

    private func addApp() {
        guard let url = SettingsOpenPanel.chooseApp(),
              let bundleID = Bundle(url: url)?.bundleIdentifier,
              !clip.excludedBundleIDs.contains(bundleID) else { return }
        settings.settings.clipboard.excludedBundleIDs.append(bundleID)
    }
}

/// Icon and name of an installed app (or its bundle id when it is not installed).
private struct ExcludedAppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    @State private var hovering = false

    /// Names for the default exclusions, so they read well even when the app is not installed.
    private static let knownNames = [
        "com.1password.1password": "1Password",
        "com.agilebits.onepassword7": "1Password 7",
        "com.bitwarden.desktop": "Bitwarden",
        "com.apple.Passwords": "Senhas",
        "com.apple.keychainaccess": "Acesso às Chaves",
    ]

    var body: some View {
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 10) {
            if let appURL {
                SettingsAppIcon(path: appURL.path, size: 22)
            } else {
                SettingsSymbolTile(symbol: "app.dashed", tint: .secondary, size: 22)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(appURL.map { SettingsItemDraft.appName(forPath: $0.path) } ?? Self.knownNames[bundleID] ?? bundleID)
                    .font(.system(size: 13))
                    .lineLimit(1)
                if appURL == nil {
                    Text("Não instalado")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            SettingsIconButton(symbol: "minus", help: "Remover da lista", action: onRemove)
                .opacity(hovering ? 1 : 0.5)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
