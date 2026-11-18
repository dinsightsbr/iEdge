import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine

/// Clipboard history (docs/SPEC.md §1.3): `ClipboardMonitor` feeds `ClipboardHistory`; this class
/// owns the files (clipboard.json and the PNGs in clipboard/), follows the clipboard settings and
/// writes entries back to the pasteboard.
@MainActor final class ClipboardStore: ObservableObject {
    /// Most recent first; `sortedEntries` (and the list) put pinned entries on top.
    @Published private(set) var entries: [ClipboardEntry]

    /// Where a real store keeps its data; nil in demo (memory only).
    struct Storage {
        var file: URL
        var imagesDirectory: URL

        static let standard = Storage(file: AppPaths.clipboardFile, imagesDirectory: AppPaths.clipboardImagesDirectory)
    }

    private let settings: SettingsStore
    let isDemo: Bool
    private let storage: Storage?
    private var history: ClipboardHistory {
        didSet { entries = history.entries }
    }
    private let monitor = ClipboardMonitor()
    private var settingsObserver: AnyCancellable?
    private var pendingSave: DispatchWorkItem?
    private var pendingTrim: DispatchWorkItem?
    /// Images that exist only in memory (demo); real entries load from their PNG path.
    private var memoryImages: [UUID: NSImage] = [:]
    /// The clipboard settings in effect. Kept here because `$settings` publishes before the new
    /// value is stored in `settings.settings`.
    private var options: ClipboardSettings
    private var thumbnailCache: [UUID: NSImage] = [:]

    static let saveDelay: TimeInterval = 0.5
    static let pasteDelay: TimeInterval = 0.12
    static let trimDelay: TimeInterval = 1.0

    convenience init(settings: SettingsStore, demo: Bool) {
        if demo {
            let (entries, images) = Self.demoEntries()
            self.init(settings: settings, storage: nil, entries: entries, images: images)
        } else {
            self.init(settings: settings, storage: .standard)
        }
    }

    /// In-memory store with the given entries (snapshots and previews).
    convenience init(settings: SettingsStore, previewEntries: [ClipboardEntry], images: [UUID: NSImage] = [:]) {
        self.init(settings: settings, storage: nil, entries: previewEntries, images: images)
    }

    /// `storage` nil keeps everything in memory; otherwise loads `storage.file` when `persist` is on.
    init(settings: SettingsStore, storage: Storage?, entries: [ClipboardEntry] = [], images: [UUID: NSImage] = [:]) {
        self.settings = settings
        self.storage = storage
        self.isDemo = storage == nil
        let clipboardSettings = settings.settings.clipboard
        self.options = clipboardSettings
        var initial = entries
        var fileIsReadable = true
        if let storage {
            if clipboardSettings.persist {
                let loaded = Self.load(from: storage.file)
                initial = loaded ?? []
                fileIsReadable = loaded != nil
            } else {
                initial = []
                try? FileManager.default.removeItem(at: storage.file)
            }
        }
        var history = ClipboardHistory(entries: initial, maxEntries: clipboardSettings.maxEntries)
        let evicted = history.setMaxEntries(clipboardSettings.maxEntries)
        self.history = history
        self.entries = history.entries
        self.memoryImages = images
        if let storage {
            evicted.forEach { ClipboardImageFiles.delete($0.content, inside: storage.imagesDirectory) }
            // With an unreadable clipboard.json every image would look orphaned; keep them so the
            // backup can still be recovered by hand.
            if fileIsReadable { Self.deleteOrphanImages(in: storage.imagesDirectory, keeping: history.entries) }
        }

        monitor.excludedBundleIDs = { [weak settings] in settings?.settings.clipboard.excludedBundleIDs ?? [] }
        monitor.onCapture = { [weak self] capture in self?.add(capture) }
        settingsObserver = settings.$settings
            .map(\.clipboard)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] new in
                MainActor.assumeIsolated { self?.apply(new) }
            }
    }

    var sortedEntries: [ClipboardEntry] { history.sorted }

    // MARK: Contract

    /// Starts watching the pasteboard. The demo store never does (it must not write images).
    func start() {
        guard !isDemo else { return }
        monitor.start()
    }

    func stop() {
        monitor.stop()
        flushTrim()
        flushSave()
        if !options.persist, let storage {
            history.entries.forEach { ClipboardImageFiles.delete($0.content, inside: storage.imagesDirectory) }
        }
    }

    /// Puts `entry` back on the pasteboard and, when `paste` and Accessibility is granted, sends ⌘V
    /// to the frontmost app shortly after (the sidebar is closing meanwhile).
    func copy(_ entry: ClipboardEntry, paste: Bool) {
        guard write(entry, to: .general) else { return }
        monitor.ignoreCurrentChange()
        history.touch(id: entry.id)
        scheduleSave()
        guard paste else { return }
        guard AXIsProcessTrusted() else {
            Log.clipboard.info("colar automaticamente pedido sem Acessibilidade; só copiado")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteDelay) {
            Self.sendPasteKeystroke()
        }
    }

    func togglePin(_ entry: ClipboardEntry) {
        apply(removed: history.togglePin(id: entry.id))
    }

    func remove(_ entry: ClipboardEntry) {
        if let removed = history.remove(id: entry.id) { apply(removed: [removed]) }
    }

    /// Removes the entries that are not pinned, and their files.
    func clear() {
        apply(removed: history.clear())
    }

    /// Image to show for an image entry (thumbnail when there is one).
    func image(for entry: ClipboardEntry) -> NSImage? {
        if let image = memoryImages[entry.id] ?? thumbnailCache[entry.id] { return image }
        guard case let .image(path, thumbnailPath, _, _, _) = entry.content,
              let image = NSImage(contentsOfFile: thumbnailPath ?? path) else { return nil }
        thumbnailCache[entry.id] = image
        return image
    }

    // MARK: Capture

    private func add(_ capture: ClipboardCapture) {
        let base = ClipboardEntry(content: .text(""), date: capture.date, sourceBundleID: capture.sourceBundleID, sourceAppName: capture.sourceAppName)
        switch capture.content {
        case .text(let text): insert(base, content: .text(text))
        case .url(let url): insert(base, content: .url(url))
        case .files(let paths): insert(base, content: .files(paths))
        case .image(let data):
            guard let directory = storage?.imagesDirectory else { return }
            let id = base.id
            Task.detached(priority: .utility) {
                do {
                    let stored = try ClipboardImageFiles.store(data, id: id, in: directory)
                    await MainActor.run {
                        self.insert(base, content: .image(path: stored.path, thumbnailPath: stored.thumbnailPath, width: stored.width, height: stored.height, byteCount: stored.byteCount))
                    }
                } catch {
                    Log.clipboard.error("falha ao gravar imagem do clipboard: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func insert(_ base: ClipboardEntry, content: ClipboardContent) {
        var entry = base
        entry.content = content
        let dropped = history.insert(entry) { existing, new in
            if case .image = new { return ClipboardImageFiles.sameImage(existing, new) }
            return existing == new
        }
        apply(removed: dropped)
    }

    // MARK: Settings

    private func apply(_ clipboard: ClipboardSettings) {
        options = clipboard
        scheduleTrim(to: clipboard.maxEntries)
        guard let storage else { return }
        if clipboard.persist {
            scheduleSave()
        } else {
            pendingSave?.cancel()
            pendingSave = nil
            try? FileManager.default.removeItem(at: storage.file)
        }
    }

    /// A smaller `maxEntries` evicts for good, and the Settings slider reports every step while it
    /// is dragged: going 200 → 20 → 200 must not throw entries away on the way. A larger limit
    /// applies at once (nothing to lose); a smaller one once the value has settled.
    private func scheduleTrim(to maxEntries: Int) {
        pendingTrim?.cancel()
        pendingTrim = nil
        guard maxEntries < history.maxEntries else {
            apply(removed: history.setMaxEntries(maxEntries), save: false)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.flushTrim() }
        }
        pendingTrim = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.trimDelay, execute: work)
    }

    /// Applies a pending smaller `maxEntries` now (on quit, and for tests).
    func flushTrim() {
        pendingTrim?.cancel()
        pendingTrim = nil
        guard options.maxEntries != history.maxEntries else { return }
        apply(removed: history.setMaxEntries(options.maxEntries))
    }

    /// Forgets entries that left the history and deletes their files.
    private func apply(removed: [ClipboardEntry], save: Bool = true) {
        for entry in removed {
            memoryImages[entry.id] = nil
            thumbnailCache[entry.id] = nil
            if let storage { ClipboardImageFiles.delete(entry.content, inside: storage.imagesDirectory) }
        }
        if save { scheduleSave() }
    }

    // MARK: Pasteboard

    /// Writes an entry with the types other apps expect. False when there was nothing to write.
    @discardableResult
    func write(_ entry: ClipboardEntry, to pasteboard: NSPasteboard) -> Bool {
        switch entry.content {
        case .text(let text):
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        case .url(let string):
            pasteboard.clearContents()
            let item = NSPasteboardItem()
            if URL(string: string) != nil { item.setString(string, forType: .URL) }
            item.setString(string, forType: .string)
            return pasteboard.writeObjects([item])
        case .files(let paths):
            let urls = paths.map { URL(fileURLWithPath: $0) as NSURL }
            guard !urls.isEmpty else { return false }
            pasteboard.clearContents()
            return pasteboard.writeObjects(urls)
        case let .image(path, _, _, _, _):
            if let image = memoryImages[entry.id] {
                pasteboard.clearContents()
                return pasteboard.writeObjects([image])
            }
            guard let png = FileManager.default.contents(atPath: path) else {
                Log.clipboard.error("imagem do clipboard sumiu do disco")
                return false
            }
            pasteboard.clearContents()
            // TIFF too: many apps only read the legacy image type.
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            if let tiff = NSImage(data: png)?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
            return pasteboard.writeObjects([item])
        }
    }

    private static func sendPasteKeystroke() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: Persistence

    private struct FileContents: Codable {
        var version = 1
        var entries: [ClipboardEntry]
    }

    private struct LossyFileContents: Decodable {
        var entries: LossyArray<ClipboardEntry>
    }

    private func scheduleSave() {
        guard let storage, options.persist else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.pendingSave = nil
                self?.save(to: storage.file)
            }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
    }

    /// Writes a pending save now (on quit, and for tests).
    func flushSave() {
        guard let pendingSave, let storage else { return }
        pendingSave.cancel()
        self.pendingSave = nil
        save(to: storage.file)
    }

    private func save(to file: URL) {
        guard options.persist else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(FileContents(entries: history.entries))
            try AppPaths.ensureDirectory(file.deletingLastPathComponent())
            try data.write(to: file, options: .atomic)
        } catch {
            Log.clipboard.error("falha ao gravar clipboard.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The saved entries: [] when there is no file yet, nil when it exists but cannot be read (it
    /// is then copied to `clipboard.json.corrompido`, since the next save replaces it).
    private static func load(from file: URL) -> [ClipboardEntry]? {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let contents = try? decoder.decode(LossyFileContents.self, from: data) else {
            let backup = file.appendingPathExtension("corrompido")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: file, to: backup)
            Log.clipboard.error("clipboard.json ilegível; histórico começa vazio (cópia em clipboard.json.corrompido)")
            return nil
        }
        // An image whose PNG was deleted behind our back cannot be pasted any more.
        return contents.entries.elements.filter { entry in
            guard case let .image(path, _, _, _, _) = entry.content else { return true }
            return FileManager.default.fileExists(atPath: path)
        }
    }

    private static func deleteOrphanImages(in directory: URL, keeping entries: [ClipboardEntry]) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let kept = Set(entries.flatMap { ClipboardImageFiles.paths(of: $0.content) }.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        for file in files where !kept.contains(file.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: Demo

    static func demoEntries() -> ([ClipboardEntry], [UUID: NSImage]) {
        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let image = ClipboardEntry(
            content: .image(path: "", thumbnailPath: nil, width: 1280, height: 800, byteCount: 412_000),
            date: ago(6), sourceBundleID: "com.apple.Preview", sourceAppName: "Pré-Visualização"
        )
        let entries = [
            ClipboardEntry(content: .text("Reunião às 15h na sala 2"), date: ago(0.2),
                           sourceBundleID: "com.apple.Notes", sourceAppName: "Notas"),
            ClipboardEntry(content: .url("https://developer.apple.com/documentation/appkit/nspanel"), date: ago(2),
                           sourceBundleID: "com.apple.Safari", sourceAppName: "Safari"),
            ClipboardEntry(content: .text("""
                O iEdge esconde uma barra lateral nas bordas da tela. Encostar o cursor na borda faz a \
                barra saltar com mola; correr o cursor ao longo dela amplia o item mais próximo, como no Dock.
                """), date: ago(4), sourceBundleID: "com.apple.TextEdit", sourceAppName: "TextEdit"),
            image,
            ClipboardEntry(content: .files(["/Users/demo/Documents/Relatório trimestral.pdf"]), date: ago(15),
                           sourceBundleID: "com.apple.finder", sourceAppName: "Finder"),
            ClipboardEntry(content: .text("swift build && swift test"), date: ago(42),
                           sourceBundleID: "com.apple.Terminal", sourceAppName: "Terminal", pinned: true),
            ClipboardEntry(content: .files(["/Users/demo/Desktop/a.png", "/Users/demo/Desktop/b.png", "/Users/demo/Desktop/c.png"]),
                           date: ago(95), sourceBundleID: "com.apple.finder", sourceAppName: "Finder"),
            ClipboardEntry(content: .text("contato@exemplo.com.br"), date: ago(60 * 26),
                           sourceBundleID: "com.apple.mail", sourceAppName: "Mail"),
        ]
        return (entries, [image.id: demoImage()])
    }

    static func demoImage() -> NSImage {
        NSImage(size: NSSize(width: 160, height: 100), flipped: false) { rect in
            let gradient = NSGradient(colors: [.systemTeal, .systemIndigo])
            gradient?.draw(in: rect, angle: 35)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: NSRect(x: 18, y: 18, width: 70, height: 46), xRadius: 6, yRadius: 6).fill()
            return true
        }
    }
}
