import Foundation

/// Everything the user can change, persisted as settings.json.
///
/// Decoding is tolerant: a missing key keeps its default and out-of-range numbers are clamped,
/// so files written by older (or newer) versions never lose the rest of the settings.
struct AppSettings: Codable, Equatable {
    var edges: Set<ScreenEdge> = [.left, .right]
    var forceEdgeWithDock = false
    var dwellMs = 150
    var pushDistance = 14.0
    var cornerExclusion = 32.0
    var magnification = 1.6
    var tileSize = 44.0
    var showLabels = true
    var haptics = true
    var items: [SidebarItem] = SidebarItem.defaults
    var screenshot = ScreenshotSettings()
    var clipboard = ClipboardSettings()
    var launchAtLogin = false
    var paused = false

    // Ranges offered by Settings; decoding clamps to them.
    static let dwellRange = 80...400
    static let pushDistanceRange = 4.0...60.0
    static let cornerExclusionRange = 0.0...200.0
    static let magnificationRange = 1.0...2.0
    static let tileSizeRange = 36.0...56.0

    /// Items shown in the sidebar, in order.
    var enabledItems: [SidebarItem] { items.filter(\.enabled) }

    func isEdgeEnabled(_ edge: ScreenEdge) -> Bool { edges.contains(edge) }

    enum CodingKeys: String, CodingKey {
        case edges, forceEdgeWithDock, dwellMs, pushDistance, cornerExclusion, magnification, tileSize
        case showLabels, haptics, items, screenshot, clipboard, launchAtLogin, paused
    }
}

extension AppSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        if let edges = try? c.decodeIfPresent(LossyArray<ScreenEdge>.self, forKey: .edges) {
            self.edges = Set(edges.elements)
        } else {
            self.edges = d.edges
        }
        forceEdgeWithDock = c.value(.forceEdgeWithDock) ?? d.forceEdgeWithDock
        dwellMs = (c.value(.dwellMs) ?? d.dwellMs).clamped(to: Self.dwellRange)
        pushDistance = (c.value(.pushDistance) ?? d.pushDistance).clamped(to: Self.pushDistanceRange)
        cornerExclusion = (c.value(.cornerExclusion) ?? d.cornerExclusion).clamped(to: Self.cornerExclusionRange)
        magnification = (c.value(.magnification) ?? d.magnification).clamped(to: Self.magnificationRange)
        tileSize = (c.value(.tileSize) ?? d.tileSize).clamped(to: Self.tileSizeRange)
        showLabels = c.value(.showLabels) ?? d.showLabels
        haptics = c.value(.haptics) ?? d.haptics
        if let items = try? c.decodeIfPresent(LossyArray<SidebarItem>.self, forKey: .items) {
            self.items = SidebarItem.normalized(items.elements)
        } else {
            self.items = d.items
        }
        screenshot = c.value(.screenshot) ?? d.screenshot
        clipboard = c.value(.clipboard) ?? d.clipboard
        launchAtLogin = c.value(.launchAtLogin) ?? d.launchAtLogin
        paused = c.value(.paused) ?? d.paused
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Sorted, so the file does not change order between saves.
        try c.encode(edges.map(\.rawValue).sorted(), forKey: .edges)
        try c.encode(forceEdgeWithDock, forKey: .forceEdgeWithDock)
        try c.encode(dwellMs, forKey: .dwellMs)
        try c.encode(pushDistance, forKey: .pushDistance)
        try c.encode(cornerExclusion, forKey: .cornerExclusion)
        try c.encode(magnification, forKey: .magnification)
        try c.encode(tileSize, forKey: .tileSize)
        try c.encode(showLabels, forKey: .showLabels)
        try c.encode(haptics, forKey: .haptics)
        try c.encode(items, forKey: .items)
        try c.encode(screenshot, forKey: .screenshot)
        try c.encode(clipboard, forKey: .clipboard)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(paused, forKey: .paused)
    }
}

enum ScreenshotDestination: String, Codable, CaseIterable {
    case file, clipboard, both

    var title: String {
        switch self {
        case .file: return "Arquivo"
        case .clipboard: return "Área de transferência"
        case .both: return "Arquivo e área de transferência"
        }
    }
}

struct ScreenshotSettings: Codable, Equatable {
    var destination: ScreenshotDestination = .both
    /// Folder chosen by the user; nil uses the system screenshot folder (or ~/Desktop).
    var folderPath: String?
    var playSound = true
    var showToast = true

    init(destination: ScreenshotDestination = .both, folderPath: String? = nil, playSound: Bool = true, showToast: Bool = true) {
        self.destination = destination
        self.folderPath = folderPath
        self.playSound = playSound
        self.showToast = showToast
    }

    private enum CodingKeys: String, CodingKey { case destination, folderPath, playSound, showToast }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ScreenshotSettings()
        destination = c.value(.destination) ?? d.destination
        folderPath = c.value(.folderPath)
        playSound = c.value(.playSound) ?? d.playSound
        showToast = c.value(.showToast) ?? d.showToast
    }
}

struct ClipboardSettings: Codable, Equatable {
    var persist = true
    var maxEntries = 50
    var autoPaste = false
    var excludedBundleIDs: [String] = ClipboardSettings.defaultExcludedBundleIDs

    static let maxEntriesRange = 20...200

    /// Password managers: 1Password (7 and 8), Bitwarden, Apple Passwords and Keychain Access.
    static let defaultExcludedBundleIDs = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.Passwords",
        "com.apple.keychainaccess",
    ]

    init(persist: Bool = true, maxEntries: Int = 50, autoPaste: Bool = false, excludedBundleIDs: [String] = ClipboardSettings.defaultExcludedBundleIDs) {
        self.persist = persist
        self.maxEntries = maxEntries
        self.autoPaste = autoPaste
        self.excludedBundleIDs = excludedBundleIDs
    }

    private enum CodingKeys: String, CodingKey { case persist, maxEntries, autoPaste, excludedBundleIDs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ClipboardSettings()
        persist = c.value(.persist) ?? d.persist
        maxEntries = (c.value(.maxEntries) ?? d.maxEntries).clamped(to: Self.maxEntriesRange)
        autoPaste = c.value(.autoPaste) ?? d.autoPaste
        excludedBundleIDs = c.value(.excludedBundleIDs) ?? d.excludedBundleIDs
    }
}

extension KeyedDecodingContainer {
    /// The value for `key`, or nil when it is missing or has the wrong type.
    func value<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
