import AppKit
import Combine

// Peça B: ClipboardMonitor (timer 0,5 s em changeCount, tipos ocultos/transitórios, apps excluídos,
// limites de tamanho, ignorar as próprias cópias), dedup subindo para o topo, limite `maxEntries`
// sem tirar fixadas, persistência em clipboard.json + clipboard/*.png quando `persist`, `copy`
// completo (imagem e arquivos) com ⌘V via CGEvent ~120 ms depois quando `paste` e AXIsProcessTrusted.
// Hoje: só memória; `copy` grava texto/URL no pasteboard; demo traz 8 entradas de exemplo.

/// Clipboard history. Most recent first; the list view puts pinned entries on top.
@MainActor final class ClipboardStore: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry]

    private let settings: SettingsStore
    let isDemo: Bool
    /// Images that exist only in memory (demo); real entries load from their PNG path.
    private var memoryImages: [UUID: NSImage] = [:]

    init(settings: SettingsStore, demo: Bool) {
        self.settings = settings
        self.isDemo = demo
        self.entries = []
        if demo {
            let (entries, images) = Self.demoEntries()
            self.entries = entries
            self.memoryImages = images
        }
    }

    func start() {
        Log.clipboard.info("ClipboardStore.start (ainda sem monitor)")
    }

    func stop() {}

    func copy(_ entry: ClipboardEntry, paste: Bool) {
        let pasteboard = NSPasteboard.general
        switch entry.content {
        case .text(let text):
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        case .url(let url):
            pasteboard.clearContents()
            pasteboard.setString(url, forType: .string)
        case .image, .files:
            Log.clipboard.info("copy de imagem/arquivos ainda não implementado")
            return
        }
        moveToTop(entry)
    }

    func togglePin(_ entry: ClipboardEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].pinned.toggle()
    }

    func remove(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
        memoryImages[entry.id] = nil
    }

    /// Removes the entries that are not pinned.
    func clear() {
        let removed = entries.filter { !$0.pinned }
        entries.removeAll { !$0.pinned }
        for entry in removed { memoryImages[entry.id] = nil }
    }

    /// Image to show for an image entry (thumbnail when there is one).
    func image(for entry: ClipboardEntry) -> NSImage? {
        if let image = memoryImages[entry.id] { return image }
        guard case let .image(path, thumbnailPath, _, _, _) = entry.content else { return nil }
        return NSImage(contentsOfFile: thumbnailPath ?? path)
    }

    private func moveToTop(_ entry: ClipboardEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var moved = entries.remove(at: index)
        moved.date = Date()
        entries.insert(moved, at: 0)
    }

    // MARK: Demo

    private static func demoEntries() -> ([ClipboardEntry], [UUID: NSImage]) {
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

    private static func demoImage() -> NSImage {
        NSImage(size: NSSize(width: 160, height: 100), flipped: false) { rect in
            let gradient = NSGradient(colors: [.systemTeal, .systemIndigo])
            gradient?.draw(in: rect, angle: 35)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: NSRect(x: 18, y: 18, width: 70, height: 46), xRadius: 6, yRadius: 6).fill()
            return true
        }
    }
}
