import AppKit
import SwiftUI

/// "Geral": login item, pause, permissions, version and quit.
struct SettingsGeneralView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: PermissionCenter
    @ObservedObject var loginItem: LoginItem
    var onQuit: () -> Void = { NSApp.terminate(nil) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.settingsSectionSpacing) {
            SettingsSection {
                SettingsToggleRow(
                    title: "Abrir ao iniciar sessão",
                    isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { settings.settings.launchAtLogin = loginItem.setEnabled($0) }
                    )
                )
                if let message = loginItem.message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                } else if loginItem.needsApproval {
                    HStack(spacing: 8) {
                        Text("Desligado em Itens de Início nos Ajustes do Sistema.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.warning)
                        Spacer(minLength: 4)
                        SettingsPillButton(title: "Abrir") { loginItem.openLoginItemsSettings() }
                    }
                }
                SettingsToggleRow(
                    title: "Pausar o iEdge",
                    detail: "As bordas param de abrir a barra até você retomar",
                    isOn: $settings.settings.paused
                )
            }

            SettingsSection(title: "Permissões") {
                ForEach(SettingsPermission.allCases) { permission in
                    SettingsPermissionRow(permission: permission, center: permissions)
                }
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("iEdge \(Self.version)")
                        .font(.system(size: 12, weight: .medium))
                    Text("© 2026 Data Insights")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                SettingsPillButton(title: "Sair do iEdge", symbol: "power", action: onQuit)
            }
            .padding(.horizontal, Theme.contentInset - Theme.rowOutset)
        }
    }

    /// "0.1.0 (1)" from the bundle; "dev" when running from `swift run` (no Info.plist).
    static var version: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "dev" }
        if let build = info?["CFBundleVersion"] as? String, !build.isEmpty { return "\(short) (\(build))" }
        return short
    }
}
