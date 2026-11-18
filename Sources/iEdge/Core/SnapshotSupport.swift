import SwiftUI

// ImageRenderer draws only pure SwiftUI. Controls backed by AppKit (segmented Picker, Toggle,
// Slider, bordered/borderless Button, ScrollView, TextField) come out as a yellow "unsupported"
// box or empty. Views that appear in `--snapshot` swap them for drawn stand-ins with
// `.snapshotStandIn { … }` and use `LiveScrollView` instead of ScrollView.

private struct IsSnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while rendering for `--snapshot`.
    var isSnapshot: Bool {
        get { self[IsSnapshotKey.self] }
        set { self[IsSnapshotKey.self] = newValue }
    }
}

private struct StandInModifier<StandIn: View>: ViewModifier {
    @Environment(\.isSnapshot) private var isSnapshot
    let standIn: StandIn

    func body(content: Content) -> some View {
        if isSnapshot { standIn } else { content }
    }
}

extension View {
    /// Shows `standIn` instead of this view when rendering a snapshot.
    func snapshotStandIn<StandIn: View>(@ViewBuilder _ standIn: () -> StandIn) -> some View {
        modifier(StandInModifier(standIn: standIn()))
    }
}

/// ScrollView in the app; the bare content in snapshots (ImageRenderer leaves ScrollView empty).
struct LiveScrollView<Content: View>: View {
    var axes: Axis.Set = .vertical
    var showsIndicators = false
    @ViewBuilder var content: Content
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        if isSnapshot {
            content
        } else {
            ScrollView(axes, showsIndicators: showsIndicators) { content }
        }
    }
}

/// Drawn look-alikes of native controls, for `.snapshotStandIn`.
enum SnapshotControls {
    /// Segmented control with `selected` highlighted.
    static func segmented(_ titles: [String], selected: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Text(title)
                    .font(.system(size: 12, weight: index == selected ? .semibold : .regular))
                    .frame(maxWidth: .infinity, minHeight: 22)
                    .background {
                        if index == selected {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.primary.opacity(0.14))
                                .padding(2)
                        }
                    }
            }
        }
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
        .frame(maxWidth: .infinity)
    }

    /// Borderless (link-like) button.
    static func plainButton(_ title: String, enabled: Bool = true) -> some View {
        Text(title)
            .font(.body)
            .foregroundStyle(enabled ? Theme.accent : Color.secondary)
    }

    /// Bordered (push) button.
    static func borderedButton(_ title: String) -> some View {
        Text(title)
            .font(.body)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.1)))
    }

    /// Switch-style toggle.
    static func toggle(_ isOn: Bool) -> some View {
        Capsule()
            .fill(isOn ? Theme.accent : Color.primary.opacity(0.15))
            .frame(width: 32, height: 18)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(Color.white).padding(2).shadow(radius: 0.5)
            }
    }

    /// Slider at `fraction` (0…1) of its track.
    static func slider(_ fraction: Double) -> some View {
        GeometryReader { proxy in
            let x = proxy.size.width * min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track).frame(height: 4)
                Capsule().fill(Theme.accent).frame(width: x, height: 4)
                Circle().fill(Color.white).frame(width: 16, height: 16).shadow(radius: 1).offset(x: x - 8)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 20)
    }
}
