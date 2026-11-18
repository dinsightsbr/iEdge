import Foundation

/// ~/Library/Application Support/iEdge/: settings.json, clipboard.json and clipboard/ (images).
///
/// Paths are computed without touching the disk (demo mode must not create anything); writers
/// call `ensureDirectory` first.
enum AppPaths {
    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("iEdge", isDirectory: true)
    }()

    static var settingsFile: URL { supportDirectory.appendingPathComponent("settings.json") }
    static var clipboardFile: URL { supportDirectory.appendingPathComponent("clipboard.json") }
    static var clipboardImagesDirectory: URL { supportDirectory.appendingPathComponent("clipboard", isDirectory: true) }

    static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
