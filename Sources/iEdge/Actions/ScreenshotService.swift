import AppKit
import CoreGraphics

/// What `screencapture` captures.
enum ScreenshotMode: Equatable {
    /// One display, 1-based as `-D` expects.
    case full(display: Int)
    case area
    case window
}

/// Where `screencapture` puts the image.
enum ScreenshotOutput: Equatable {
    case file(String)
    case clipboard
}

/// Pure pieces of a capture: arguments, file name, display index, folder (docs/SPEC.md §1.4).
enum ScreenshotCommand {
    static let executable = URL(fileURLWithPath: "/usr/sbin/screencapture")
    static let captureToolURL = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
    static let screenRecordingSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")

    static func arguments(mode: ScreenshotMode, output: ScreenshotOutput, playSound: Bool) -> [String] {
        var arguments: [String] = []
        if !playSound { arguments.append("-x") }
        switch mode {
        case .full(let display): arguments += ["-D", String(max(1, display))]
        case .area: arguments += ["-i", "-s"]
        case .window: arguments += ["-i", "-w"]
        }
        switch output {
        case .file(let path): arguments.append(path)
        case .clipboard: arguments.append("-c")
        }
        return arguments
    }

    /// `Captura de Tela 2026-11-18 às 14.05.33.png`, in the given time zone.
    static func fileName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'às' HH.mm.ss"
        return "Captura de Tela \(formatter.string(from: date)).png"
    }

    /// `name.png`, or `name (2).png`, `name (3).png`… when taken (two captures in one second).
    static func uniqueFileURL(in folder: URL, name: String, exists: (URL) -> Bool) -> URL {
        let first = folder.appendingPathComponent(name)
        guard exists(first) else { return first }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for n in 2...999 {
            let candidate = folder.appendingPathComponent("\(base) (\(n)).\(ext)")
            if !exists(candidate) { return candidate }
        }
        return folder.appendingPathComponent("\(base) \(UUID().uuidString).\(ext)")
    }

    /// `-D` value of a display: its position in `CGGetActiveDisplayList` + 1.
    static func displayNumber(of id: CGDirectDisplayID, in activeDisplays: [CGDirectDisplayID]) -> Int? {
        activeDisplays.firstIndex(of: id).map { $0 + 1 }
    }

    /// Chosen folder, else the system screenshot folder, else ~/Desktop; each only if it is a folder.
    static func folder(custom: String?, systemLocation: String?, home: URL, isDirectory: (URL) -> Bool) -> URL {
        for path in [custom, systemLocation].compactMap({ $0 }) where !path.isEmpty {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            if isDirectory(url) { return url }
        }
        return home.appendingPathComponent("Desktop", isDirectory: true)
    }
}

/// Runs screen captures with `/usr/sbin/screencapture` and shows the preview toast.
@MainActor final class ScreenshotService {
    /// Time for the closed sidebar to leave the screen before a full-screen capture.
    static let fullScreenDelay: TimeInterval = 0.15

    private let settings: SettingsStore
    private let toast: CaptureToastController
    private var isCapturing = false

    init(settings: SettingsStore, toast: CaptureToastController) {
        self.settings = settings
        self.toast = toast
    }

    static var hasScreenRecordingPermission: Bool { CGPreflightScreenCaptureAccess() }

    func capture(_ kind: ActionKind, context: ActionContext) {
        guard !isCapturing else { return }
        guard ensurePermission(context: context) else { return }
        // The preview of the previous capture stays 3 s; it must not end up in this one.
        toast.dismiss(animated: false)

        let mode: ScreenshotMode
        switch kind {
        case .screenshotFull: mode = .full(display: Self.displayNumber(for: context.screen) ?? 1)
        case .screenshotArea: mode = .area
        case .screenshotWindow: mode = .window
        default: return
        }

        let options = settings.settings.screenshot
        let fileURL: URL?
        if options.destination == .clipboard {
            fileURL = nil
        } else {
            let folder = ScreenshotCommand.folder(
                custom: options.folderPath,
                systemLocation: UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
                home: FileManager.default.homeDirectoryForCurrentUser,
                isDirectory: Self.isDirectory
            )
            fileURL = ScreenshotCommand.uniqueFileURL(in: folder, name: ScreenshotCommand.fileName(for: Date())) {
                FileManager.default.fileExists(atPath: $0.path)
            }
        }
        let output: ScreenshotOutput = fileURL.map { .file($0.path) } ?? .clipboard
        let arguments = ScreenshotCommand.arguments(mode: mode, output: output, playSound: options.playSound)
        let changeCount = NSPasteboard.general.changeCount
        let delay = mode == .area || mode == .window ? 0 : Self.fullScreenDelay

        isCapturing = true
        Task { @MainActor in
            defer { isCapturing = false }
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            let result = await ActionProcess.run(ScreenshotCommand.executable, arguments: arguments, timeout: nil)
            finish(result: result, fileURL: fileURL, previousChangeCount: changeCount, context: context)
        }
    }

    func openCaptureTool(context: ActionContext) {
        Task { @MainActor in
            do {
                _ = try await NSWorkspace.shared.openApplication(at: ScreenshotCommand.captureToolURL, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                Log.actions.error("falha ao abrir Captura de Tela: \(error.localizedDescription, privacy: .public)")
                toast.showMessage(title: "Não foi possível abrir a Captura de Tela", detail: error.localizedDescription, context: context)
            }
        }
    }

    // MARK: Private

    private func finish(result: ActionProcessResult, fileURL: URL?, previousChangeCount: Int, context: ActionContext) {
        if let launchError = result.launchError {
            Log.actions.error("screencapture não iniciou: \(launchError, privacy: .public)")
            toast.showMessage(title: "Captura falhou", detail: launchError, context: context)
            return
        }
        let image: NSImage?
        if let fileURL {
            // Esc during an interactive capture: no file, no toast.
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                Log.actions.info("captura cancelada")
                return
            }
            image = NSImage(contentsOf: fileURL)
            if settings.settings.screenshot.destination == .both {
                Self.copyImageFile(fileURL)
            }
        } else {
            guard NSPasteboard.general.changeCount != previousChangeCount else {
                Log.actions.info("captura cancelada")
                return
            }
            image = NSImage(pasteboard: .general)
        }
        Log.actions.info("captura feita")
        guard settings.settings.screenshot.showToast, let image else { return }
        toast.showCapture(image: image, fileURL: fileURL, context: context)
    }

    /// Without the permission screencapture still "works" but only sees the wallpaper, so ask
    /// first and explain instead.
    private func ensurePermission(context: ActionContext) -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        // Shows the system prompt the first time; afterwards only the Settings toggle helps.
        if CGRequestScreenCaptureAccess() { return true }
        Log.actions.info("sem permissão de Gravação de Tela")
        toast.showMessage(
            symbol: "rectangle.dashed.badge.record",
            title: "Permitir Gravação de Tela",
            detail: "O iEdge precisa dessa permissão para capturar a tela.",
            actionTitle: "Abrir Ajustes do Sistema",
            context: context
        ) {
            if let url = ScreenshotCommand.screenRecordingSettingsURL { NSWorkspace.shared.open(url) }
        }
        return false
    }

    /// PNG and TIFF of the saved file, so it also lands in the clipboard history as an image.
    private static func copyImageFile(_ url: URL) {
        guard let png = try? Data(contentsOf: url) else { return }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    private static func displayNumber(for screen: NSScreen) -> Int? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return nil }
        return ScreenshotCommand.displayNumber(of: CGDirectDisplayID(number.uint32Value), in: Array(displays.prefix(Int(count))))
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
