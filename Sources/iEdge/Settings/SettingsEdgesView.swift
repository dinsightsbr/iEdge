import SwiftUI

/// "Bordas": which edges trigger the sidebar and how it feels.
struct SettingsEdgesView: View {
    @ObservedObject var settings: SettingsStore
    /// Side the Dock is on, if left or right (read when Settings opens).
    var dockEdge: ScreenEdge?
    /// "Testar à esquerda/direita": opens the sidebar on that edge.
    var onTest: (ScreenEdge) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.settingsSectionSpacing) {
            SettingsSection(title: "Onde abrir") {
                ForEach(ScreenEdge.allCases, id: \.self) { edge in
                    edgeRow(edge)
                }
            }

            SettingsSection(title: "Gatilho") {
                SettingsSliderRow(
                    title: "Tempo na borda",
                    value: Binding(
                        get: { Double(settings.settings.dwellMs) },
                        set: { settings.settings.dwellMs = Int($0.rounded()) }
                    ),
                    range: Double(AppSettings.dwellRange.lowerBound)...Double(AppSettings.dwellRange.upperBound),
                    step: 10
                ) { "\(Int($0)) ms" }

                SettingsSliderRow(
                    title: "Empurrão",
                    value: $settings.settings.pushDistance,
                    range: AppSettings.pushDistanceRange,
                    step: 1
                ) { "\(Int($0)) pt" }

                Text("Abre ao parar o cursor na borda por esse tempo, ou ao empurrá-lo contra ela por essa distância.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsSection(title: "Barra") {
                SettingsSliderRow(
                    title: "Ampliação",
                    value: $settings.settings.magnification,
                    range: AppSettings.magnificationRange,
                    step: 0.1
                ) { Self.magnificationText($0) }

                SettingsSliderRow(
                    title: "Tamanho dos itens",
                    value: $settings.settings.tileSize,
                    range: AppSettings.tileSizeRange,
                    step: 2
                ) { "\(Int($0)) pt" }

                SettingsToggleRow(title: "Mostrar o nome do item", isOn: $settings.settings.showLabels)
                SettingsToggleRow(
                    title: "Toque no trackpad",
                    detail: "Um toque leve ao passar de um item para outro",
                    isOn: $settings.settings.haptics
                )
            }

            HStack(spacing: 8) {
                SettingsPillButton(title: "Testar à esquerda", symbol: "sidebar.left") { onTest(.left) }
                SettingsPillButton(title: "Testar à direita", symbol: "sidebar.right") { onTest(.right) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.contentInset - Theme.rowOutset)
        }
    }

    static func magnificationText(_ value: Double) -> String {
        if value < 1.05 { return "Desligada" }
        let formatted = value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "pt_BR")))
        return formatted + "×"
    }

    @ViewBuilder private func edgeRow(_ edge: ScreenEdge) -> some View {
        let isOn = Binding(
            get: { settings.settings.isEdgeEnabled(edge) },
            set: { on in
                if on { settings.settings.edges.insert(edge) } else { settings.settings.edges.remove(edge) }
            }
        )
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                SettingsSymbolTile(symbol: edge == .left ? "rectangle.lefthalf.inset.filled" : "rectangle.righthalf.inset.filled")
                SettingsToggleRow(title: edge == .left ? "Borda esquerda" : "Borda direita", isOn: isOn)
            }
            if edge == dockEdge, settings.settings.isEdgeEnabled(edge) {
                dockWarning
            }
        }
    }

    private var dockWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("O Dock está nesta borda. A barra não abre aqui para não atrapalhar o Dock.", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(settings.settings.forceEdgeWithDock ? Color.secondary : Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
            SettingsToggleRow(title: "Abrir mesmo assim", isOn: $settings.settings.forceEdgeWithDock)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius - 2, style: .continuous)
                .fill(Theme.warning.opacity(settings.settings.forceEdgeWithDock ? 0.04 : 0.1))
        )
    }
}

/// Side of the screen the Dock is on (`com.apple.dock` `orientation`), nil when at the bottom.
enum SettingsDockSide {
    static func current() -> ScreenEdge? {
        guard let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") else { return nil }
        return ScreenEdge(rawValue: orientation)
    }
}
