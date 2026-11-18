import Foundation
import Combine

/// Owns `AppSettings` and keeps settings.json in sync: every change is saved after a short
/// debounce, so dragging a slider writes once, not on every step.
@MainActor final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            scheduleSave()
        }
    }

    let isDemo: Bool
    /// nil in demo mode: nothing is read or written.
    let fileURL: URL?
    private var pendingSave: DispatchWorkItem?

    static let saveDelay: TimeInterval = 0.4

    /// demo: does not read or write the disk.
    convenience init(demo: Bool) {
        self.init(fileURL: demo ? nil : AppPaths.settingsFile)
    }

    /// Reads `fileURL` (if any) and saves back to it. Also used by tests with a temporary file.
    init(fileURL: URL?) {
        self.fileURL = fileURL
        self.isDemo = fileURL == nil
        self.settings = fileURL.flatMap(Self.load(from:)) ?? AppSettings()
    }

    // MARK: Convenience mutations

    func resetItems() {
        settings.items = SidebarItem.defaults
    }

    func update(_ item: SidebarItem) {
        guard let index = settings.items.firstIndex(where: { $0.id == item.id }) else { return }
        settings.items[index] = item
    }

    /// Custom items only; built-ins can be turned off but not removed.
    func remove(_ item: SidebarItem) {
        guard !item.isBuiltIn else { return }
        settings.items.removeAll { $0.id == item.id }
    }

    // MARK: Persistence

    /// Writes any pending change now (on quit).
    func flush() {
        guard let pendingSave else { return }
        pendingSave.cancel()
        self.pendingSave = nil
        save()
    }

    private func scheduleSave() {
        guard fileURL != nil else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.pendingSave = nil
                self?.save()
            }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
    }

    private func save() {
        guard let fileURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try AppPaths.ensureDirectory(fileURL.deletingLastPathComponent())
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.settings.error("falha ao gravar settings.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> AppSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            // Keep the unreadable file aside instead of silently overwriting it on the next save.
            let backup = url.appendingPathExtension("corrompido")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: url, to: backup)
            Log.settings.error("settings.json ilegível, usando padrões: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
