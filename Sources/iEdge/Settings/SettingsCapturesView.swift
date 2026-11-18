import SwiftUI

/// "Capturas": where screenshots go and how they are announced.
struct SettingsCapturesView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: PermissionCenter

    private var screenshot: ScreenshotSettings { settings.settings.screenshot }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.settingsSectionSpacing) {
            SettingsSection(title: "Destino") {
                SettingsSegmented(options: ScreenshotDestination.allCases, selection: $settings.settings.screenshot.destination) {
                    Self.shortTitle($0)
                }
                Text(Self.destinationDetail(screenshot.destination))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsSection(title: "Pasta") {
                HStack(spacing: 10) {
                    SettingsSymbolTile(symbol: "folder")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(folderPath.settingsAbbreviatedPath)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(screenshot.folderPath == nil ? "Pasta de capturas do sistema" : "Escolhida por você")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .opacity(screenshot.destination == .clipboard ? 0.5 : 1)
                HStack(spacing: 8) {
                    SettingsPillButton(title: "Escolher…", action: chooseFolder)
                    SettingsPillButton(title: "Usar a do sistema", enabled: screenshot.folderPath != nil) {
                        settings.settings.screenshot.folderPath = nil
                    }
                    Spacer(minLength: 0)
                }
            }

            SettingsSection(title: "Ao capturar") {
                SettingsToggleRow(title: "Tocar som", isOn: $settings.settings.screenshot.playSound)
                SettingsToggleRow(
                    title: "Mostrar prévia",
                    detail: "Miniatura na borda por 3 s: clique para abrir, arraste para levar o arquivo",
                    isOn: $settings.settings.screenshot.showToast
                )
            }

            SettingsSection(title: "Permissão") {
                SettingsPermissionRow(permission: .screenCapture, center: permissions)
            }
        }
    }

    private var folderPath: String {
        screenshot.folderPath ?? SettingsScreenshotFolder.system()
    }

    private func chooseFolder() {
        guard let url = SettingsOpenPanel.chooseFolder(startingAt: folderPath) else { return }
        settings.settings.screenshot.folderPath = url.path
    }

    static func shortTitle(_ destination: ScreenshotDestination) -> String {
        switch destination {
        case .file: return "Arquivo"
        case .clipboard: return "Clipboard"
        case .both: return "Ambos"
        }
    }

    static func destinationDetail(_ destination: ScreenshotDestination) -> String {
        switch destination {
        case .file: return "Grava um PNG na pasta abaixo."
        case .clipboard: return "Só copia a imagem; nenhum arquivo é gravado."
        case .both: return "Grava o PNG e copia a imagem (ela entra no histórico do clipboard)."
        }
    }
}

/// Folder macOS saves screenshots in (`com.apple.screencapture` `location`), or ~/Desktop.
enum SettingsScreenshotFolder {
    static func system() -> String {
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !location.isEmpty {
            return (location as NSString).expandingTildeInPath
        }
        return (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")
    }
}
