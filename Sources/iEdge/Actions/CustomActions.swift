import AppKit

/// Shortcuts the user creates in Settings (docs/SPEC.md §1.5): open an app, open a link or file,
/// run a Shortcuts shortcut, run a shell command. Failures become a short toast.
@MainActor final class CustomActions {
    nonisolated static let shortcutsExecutable = URL(fileURLWithPath: "/usr/bin/shortcuts")
    nonisolated static let shellExecutable = URL(fileURLWithPath: "/bin/zsh")

    private let toast: CaptureToastController

    init(toast: CaptureToastController) {
        self.toast = toast
    }

    func run(_ item: SidebarItem, context: ActionContext) {
        switch item.kind {
        case .openApp(let path):
            openApp(path: path, title: item.title, context: context)
        case .openURL(let string):
            open(link: string, context: context)
        case .shortcut, .shell:
            guard let command = Self.processCommand(for: item.kind) else {
                fail(title: "\(item.title): nada para executar", detail: nil, context: context)
                return
            }
            let failureTitle = item.kind.isShortcutKind ? "Atalho \u{201C}\(item.title)\u{201D} falhou" : "\u{201C}\(item.title)\u{201D} falhou"
            Task { @MainActor in
                let result = await ActionProcess.run(command.executable, arguments: command.arguments)
                guard !result.succeeded else { return }
                Log.actions.error("\(item.kind.kindTitle, privacy: .public) falhou: \(result.failureDetail, privacy: .public)")
                fail(title: failureTitle, detail: result.failureDetail, context: context)
            }
        default:
            break
        }
    }

    // MARK: Pure

    /// Executable and argument array for the kinds that run a process; nil for the others or an
    /// empty name/command. The command string is passed to zsh as one argument, never spliced.
    nonisolated static func processCommand(for kind: ActionKind) -> (executable: URL, arguments: [String])? {
        switch kind {
        case .shortcut(let name):
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : (shortcutsExecutable, ["run", name])
        case .shell(let command):
            return command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : (shellExecutable, ["-lc", command])
        default:
            return nil
        }
    }

    /// What "Abrir link/arquivo" opens: a URL with a scheme, or a path (`~` expanded) as a file URL.
    nonisolated static func target(forLink string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        }
        if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty {
            return url
        }
        // "example.com" without a scheme: treat as a web address.
        if trimmed.contains("."), !trimmed.contains(" "), let url = URL(string: "https://\(trimmed)") {
            return url
        }
        return nil
    }

    // MARK: Private

    private func openApp(path: String, title: String, context: ActionContext) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            fail(title: "App não encontrado", detail: url.lastPathComponent, context: context)
            return
        }
        Task { @MainActor in
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                fail(title: "Não foi possível abrir \(title)", detail: error.localizedDescription, context: context)
            }
        }
    }

    private func open(link string: String, context: ActionContext) {
        guard let url = Self.target(forLink: string) else {
            fail(title: "Link inválido", detail: string, context: context)
            return
        }
        if url.isFileURL, !FileManager.default.fileExists(atPath: url.path) {
            fail(title: "Arquivo não encontrado", detail: url.path, context: context)
            return
        }
        if !NSWorkspace.shared.open(url) {
            fail(title: "Não foi possível abrir", detail: string, context: context)
        }
    }

    private func fail(title: String, detail: String?, context: ActionContext) {
        toast.showMessage(title: title, detail: detail, context: context)
    }
}

private extension ActionKind {
    var isShortcutKind: Bool {
        if case .shortcut = self { return true }
        return false
    }
}
