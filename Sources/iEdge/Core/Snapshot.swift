import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Demo stores handed to every snapshot.
@MainActor
struct SnapshotContext {
    let settings: SettingsStore
    let clipboard: ClipboardStore
}

/// One renderable view of the catalog.
struct SnapshotEntry {
    let name: String
    /// Corner radius of the glass the view normally sits on; the snapshot draws a translucent
    /// gray shape there instead (glass does not render outside a window). nil draws none.
    var glassRadius: CGFloat?
    let make: @MainActor (SnapshotContext) -> AnyView
}

/// Every piece adds its own entries in its own file (`Sidebar/Snapshots+Sidebar.swift`,
/// `Clipboard/Snapshots+Clipboard.swift`, `Settings/Snapshots+Settings.swift`).
enum SnapshotCatalog {
    @MainActor static var all: [SnapshotEntry] { sidebar + clipboard + settings }
}

/// `--snapshot <name> --out <file.png> [--scheme light|dark]`: renders a view with ImageRenderer
/// at scale 2, writes the PNG and exits, without opening a window or a status item.
@MainActor
enum Snapshot {
    static func run(_ options: LaunchOptions) -> Int32 {
        guard let name = options.snapshot else { return 1 }
        let entries = SnapshotCatalog.all

        if name == "list" {
            writeLine(entries.map(\.name).joined(separator: "\n"), to: .standardOutput)
            return 0
        }
        guard let entry = entries.first(where: { $0.name == name }) else {
            writeLine("snapshot desconhecido: \(name) (use --snapshot list)", to: .standardError)
            return 1
        }

        // No window and no Dock icon, but AppKit initialised so fonts, symbols and app icons resolve.
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let dark = options.scheme == .dark
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        let settings = SettingsStore(demo: true)
        let context = SnapshotContext(settings: settings, clipboard: ClipboardStore(settings: settings, demo: true))
        let output = options.snapshotOut ?? "\(name).png"

        let content = framed(entry.make(context), entry: entry, dark: dark)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        // NSColor-backed colors and app icons resolve against the current drawing appearance.
        var image: CGImage?
        if let appearance = app.appearance {
            appearance.performAsCurrentDrawingAppearance { image = renderer.cgImage }
        } else {
            image = renderer.cgImage
        }
        guard let image else {
            writeLine("falha ao renderizar \(name)", to: .standardError)
            return 1
        }
        guard writePNG(image, to: URL(fileURLWithPath: output)) else {
            writeLine("falha ao gravar \(output)", to: .standardError)
            return 1
        }
        Log.snapshot.info("snapshot \(name, privacy: .public) gravado em \(output, privacy: .public)")
        writeLine(output, to: .standardOutput)
        return 0
    }

    /// The view on a gray translucent stand-in for the glass, over a plain canvas.
    private static func framed(_ view: AnyView, entry: SnapshotEntry, dark: Bool) -> AnyView {
        let canvas = dark ? Color(white: 0.16) : Color(white: 0.93)
        let glassFill = dark ? Color.gray.opacity(0.35) : Color.gray.opacity(0.18)
        return AnyView(
            view
                .background {
                    if let radius = entry.glassRadius {
                        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(glassFill)
                    }
                }
                .padding(24)
                .background(canvas)
                .environment(\.locale, Locale(identifier: "pt_BR"))
                .environment(\.isSnapshot, true)
        )
    }

    private static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    private static func writeLine(_ text: String, to handle: FileHandle) {
        handle.write(Data((text + "\n").utf8))
    }
}
