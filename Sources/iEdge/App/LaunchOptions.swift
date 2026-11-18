import Foundation

/// Development flags (docs/SPEC.md §3.2). Parsing is pure so it can be tested.
struct LaunchOptions: Equatable {
    enum Scheme: String { case light, dark }

    /// `--demo`: settings and clipboard in memory, with sample entries.
    var demo = false
    /// `--show left|right`: open the sidebar on that edge of the main screen at launch.
    var show: ScreenEdge?
    /// `--pin`: the sidebar does not close by itself.
    var pin = false
    /// `--hover 0.0…1.0`: simulated cursor at that fraction of the sidebar's height (top = 0).
    var hover: Double?
    /// `--flyout`: open the clipboard flyout with the sidebar.
    var flyout = false
    /// `--settings [tab]`: open Settings on that tab (default Itens).
    var settings: SettingsTab?
    /// `--frame-file <path>`: write the on-screen rectangles of the open panels 1.5 s after opening.
    var frameFile: String?
    /// `--snapshot <name>|list`.
    var snapshot: String?
    /// `--out <file.png>` for `--snapshot`.
    var snapshotOut: String?
    /// `--scheme light|dark`, when given. `--snapshot` defaults to light; with `--backdrop` it also
    /// sets the running app's appearance, which otherwise follows the system.
    var schemeOverride: Scheme?
    /// `--backdrop`: a full-screen gradient window behind the panels, so screenshots of the running
    /// app show nothing of the user's screen.
    var backdrop = false

    /// Scheme for `--snapshot`.
    var scheme: Scheme { schemeOverride ?? .light }

    init() {}

    init(arguments: [String]) {
        // The first element is the executable path.
        let args = Array(arguments.dropFirst())
        func value(for flag: String) -> String? {
            guard let index = args.firstIndex(of: flag) else { return nil }
            let next = index + 1
            guard next < args.count, !args[next].hasPrefix("--") else { return nil }
            return args[next]
        }

        demo = args.contains("--demo")
        show = value(for: "--show").flatMap(ScreenEdge.init(rawValue:))
        pin = args.contains("--pin")
        hover = value(for: "--hover").flatMap(Double.init).map { min(max($0, 0), 1) }
        flyout = args.contains("--flyout")
        if args.contains("--settings") {
            settings = value(for: "--settings").flatMap { SettingsTab(rawValue: $0.lowercased()) } ?? .itens
        }
        frameFile = value(for: "--frame-file")
        snapshot = value(for: "--snapshot")
        snapshotOut = value(for: "--out")
        schemeOverride = value(for: "--scheme").flatMap(Scheme.init(rawValue:))
        backdrop = args.contains("--backdrop")
    }

    /// Anything that opens UI on launch (and therefore needs a frame file, if asked).
    var opensUIAtLaunch: Bool { show != nil || settings != nil }
}
