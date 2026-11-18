import AppKit
import SwiftUI

// Building blocks shared by the Settings tabs. Every native control is wrapped here once with its
// `.snapshotStandIn`, so the tab views stay plain and still render in `--snapshot`.

extension Theme {
    /// Vertical gap between sections of a tab.
    static let settingsSectionSpacing: CGFloat = 12
    /// Gap between rows inside a section card.
    static let settingsRowSpacing: CGFloat = 10
    /// Tallest the scrolling tab content gets before it scrolls.
    static let settingsMaxContentHeight: CGFloat = 520
    static let settingsIconSize: CGFloat = 26
}

/// A titled band: caption above, rows on a faint card.
struct SettingsSection<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.contentInset - Theme.rowOutset)
            }
            CardView(padding: 12) {
                VStack(alignment: .leading, spacing: Theme.settingsRowSpacing) {
                    content
                }
            }
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.contentInset - Theme.rowOutset)
            }
        }
    }
}

/// Title (and optional detail) on the left, a switch on the right.
struct SettingsToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            SettingsRowLabel(title: title, detail: detail)
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .snapshotStandIn { SnapshotControls.toggle(isOn) }
        }
    }
}

struct SettingsRowLabel: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 13))
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Title and current value on one line, the slider under them.
struct SettingsSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    /// Text shown on the right ("150 ms", "1,6×").
    let valueText: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                Text(valueText(value))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            slider
                .controlSize(.small)
                .snapshotStandIn {
                    SnapshotControls.slider((value - range.lowerBound) / max(range.upperBound - range.lowerBound, .ulpOfOne))
                }
        }
    }

    @ViewBuilder private var slider: some View {
        if let step {
            Slider(value: $value, in: range, step: step) { Text(title) }.labelsHidden()
        } else {
            Slider(value: $value, in: range) { Text(title) }.labelsHidden()
        }
    }
}

/// Native segmented control over any list of options.
struct SettingsSegmented<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.self) { option in
                Text(title(option)).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .snapshotStandIn {
            SnapshotControls.segmented(options.map(title), selected: options.firstIndex(of: selection) ?? 0)
        }
    }
}

/// Rounded text field; in snapshots a drawn look-alike.
struct SettingsTextField: View {
    let placeholder: String
    @Binding var text: String
    var monospaced = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 13))
            .snapshotStandIn {
                Text(text.isEmpty ? placeholder : text)
                    .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 13))
                    .foregroundStyle(text.isEmpty ? Color.secondary.opacity(0.7) : Color.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
            }
    }
}

/// Capsule button drawn in SwiftUI (renders the same in the app and in snapshots), in the
/// faint fill of the iSessions header buttons. `prominent` uses the accent color.
struct SettingsPillButton: View {
    enum Style { case normal, prominent, destructive }

    let title: String
    var symbol: String?
    var style: Style = .normal
    var enabled = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                }
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(minHeight: 24)
            .background(Capsule(style: .continuous).fill(fill))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovering = $0 }
    }

    private var foreground: Color {
        switch style {
        case .normal: return .primary
        case .prominent: return .white
        case .destructive: return Theme.critical
        }
    }

    private var fill: Color {
        switch style {
        case .normal, .destructive: return Color.primary.opacity(hovering ? 0.12 : 0.07)
        case .prominent: return Theme.accent.opacity(hovering ? 0.85 : 1)
        }
    }
}

/// Round icon-only button (↑↓, edit, remove), like the header buttons of iSessions.
struct SettingsIconButton: View {
    let symbol: String
    var help: String
    var enabled = true
    var size: CGFloat = 22
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.45, weight: .semibold))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.12 : 0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// A destructive action that asks once, inline ("Limpar histórico" → "Limpar tudo? Limpar · Cancelar").
struct SettingsConfirmButton: View {
    let title: String
    var symbol: String?
    let question: String
    let confirmTitle: String
    var enabled = true
    let action: () -> Void

    @State private var confirming = false

    var body: some View {
        HStack(spacing: 8) {
            if confirming {
                Text(question)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 4)
                SettingsPillButton(title: "Cancelar") { confirming = false }
                SettingsPillButton(title: confirmTitle, style: .destructive) {
                    confirming = false
                    action()
                }
            } else {
                SettingsPillButton(title: title, symbol: symbol, enabled: enabled) { confirming = true }
            }
        }
    }
}

/// State of one permission with the button that grants it.
struct SettingsPermissionRow: View {
    let permission: SettingsPermission
    @ObservedObject var center: PermissionCenter

    var body: some View {
        let granted = center.isGranted(permission)
        HStack(spacing: 10) {
            SettingsSymbolTile(symbol: permission.symbol, tint: granted ? Theme.ok : Theme.warning)
            SettingsRowLabel(title: permission.title, detail: permission.purpose)
            Spacer(minLength: 6)
            if granted {
                Label("Concedida", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.ok)
                    .fixedSize()
            } else {
                SettingsPillButton(title: center.asked.contains(permission) ? "Abrir Ajustes" : "Conceder", style: .prominent) {
                    center.request(permission)
                }
                    .fixedSize()
            }
        }
    }
}

/// SF Symbol on a small rounded tile, the icon column of the lists.
struct SettingsSymbolTile: View {
    let symbol: String
    var tint: Color = .primary
    var size: CGFloat = Theme.settingsIconSize

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(Theme.tileFill)
            )
    }
}

/// App icon for a bundle path at list size.
struct SettingsAppIcon: View {
    let path: String
    var size: CGFloat = Theme.settingsIconSize

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// `NSOpenPanel` from the non-activating Settings panel. While it runs, Settings must not close
/// when it loses key status; `isPresenting` tells the status item controller so.
@MainActor enum SettingsOpenPanel {
    private(set) static var isPresenting = false

    static func chooseApp(startingAt directory: String = "/Applications") -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        panel.prompt = "Escolher"
        panel.message = "Escolha um app"
        return run(panel)
    }

    static func chooseFolder(startingAt directory: String?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let directory { panel.directoryURL = URL(fileURLWithPath: directory, isDirectory: true) }
        panel.prompt = "Escolher"
        panel.message = "Pasta onde as capturas são gravadas"
        return run(panel)
    }

    private static func run(_ panel: NSOpenPanel) -> URL? {
        let previousKey = NSApp.keyWindow
        isPresenting = true
        defer {
            previousKey?.makeKeyAndOrderFront(nil)
            // The resign-key check of Settings runs on the next turn; clear the flag after it.
            DispatchQueue.main.async { MainActor.assumeIsolated { isPresenting = false } }
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}

extension String {
    /// `/Users/me/Desktop` → `~/Desktop`, for showing paths.
    var settingsAbbreviatedPath: String { (self as NSString).abbreviatingWithTildeInPath }
}
