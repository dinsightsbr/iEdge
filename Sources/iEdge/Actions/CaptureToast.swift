import AppKit
import SwiftUI

extension Theme {
    static let toastCaptureWidth: CGFloat = 232
    static let toastMessageWidth: CGFloat = 300
    /// Gap between the toast and the screen's visible edges.
    static let toastEdgeGap: CGFloat = 12
}

/// What the toast card shows.
enum CaptureToastContent {
    /// Thumbnail of a capture; `fileName` nil when it went only to the clipboard.
    case capture(image: NSImage, fileName: String?)
    /// Short notice (failed shortcut, missing permission). `actionTitle` hints what a click does.
    case message(symbol: String, title: String, detail: String?, actionTitle: String?)
}

/// The glass card's content (docs/SPEC.md §1.4 "Prévia" and §1.5 failures).
struct CaptureToastView: View {
    let content: CaptureToastContent

    var body: some View {
        switch content {
        case let .capture(image, fileName):
            captureCard(image: image, fileName: fileName)
        case let .message(symbol, title, detail, actionTitle):
            messageCard(symbol: symbol, title: title, detail: detail, actionTitle: actionTitle)
        }
    }

    private func captureCard(image: NSImage, fileName: String?) -> some View {
        let inner = Theme.toastCaptureWidth - 2 * Theme.rowOutset
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 16.0 / 10.0
        let height = min(inner / max(aspect, 0.1), 150)
        return VStack(alignment: .leading, spacing: 8) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: inner, maxHeight: height)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                Image(systemName: fileName == nil ? "doc.on.clipboard" : "photo")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(fileName == nil ? "Copiada para a área de transferência" : "Captura salva")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if fileName != nil {
                    Text("Arraste ou clique")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(Theme.rowOutset)
        .padding(.bottom, 2)
        .frame(width: Theme.toastCaptureWidth)
    }

    private func messageCard(symbol: String, title: String, detail: String?, actionTitle: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.warning)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.tileFill))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let actionTitle {
                    Text(actionTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: Theme.toastMessageWidth)
    }
}

/// One toast at a time: a glass card that springs out of the sidebar's edge near the bottom of
/// the screen and leaves after 3 s (the countdown pauses while the cursor is over it).
@MainActor final class CaptureToastController {
    static let lifetime: TimeInterval = 3
    private static let tick: TimeInterval = 0.1

    static let configuration = GlassPanel.Configuration(
        radius: Theme.toastRadius,
        margins: NSEdgeInsets(top: 14, left: 22, bottom: 30, right: 22),
        level: .statusBar,
        collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle],
        canBecomeKey: false
    )

    private var panel: GlassPanel?
    private var edge: ScreenEdge = .right
    private var countdown: Timer?
    private var remaining: TimeInterval = 0

    /// Capture preview. Click opens the file in Preview; dragging the card drags the file.
    func showCapture(image: NSImage, fileURL: URL?, context: ActionContext) {
        present(.capture(image: image, fileName: fileURL?.lastPathComponent), dragFile: fileURL, dragImage: image, context: context) {
            guard let fileURL else { return }
            Self.openInPreview(fileURL)
        }
    }

    /// Short notice; a click runs `action` (if any) and closes it.
    func showMessage(symbol: String = "exclamationmark.triangle.fill", title: String, detail: String? = nil,
                     actionTitle: String? = nil, context: ActionContext, action: (() -> Void)? = nil) {
        present(.message(symbol: symbol, title: title, detail: detail, actionTitle: actionTitle), dragFile: nil, dragImage: nil, context: context, onClick: action)
    }

    func dismiss(animated: Bool = true) {
        countdown?.invalidate()
        countdown = nil
        guard let panel else { return }
        self.panel = nil
        guard animated else {
            panel.orderOut(nil)
            return
        }
        let hidden = Self.offscreen(panel.frame, edge: edge, screen: panel.screen)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(hidden, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    // MARK: Private

    private func present(_ content: CaptureToastContent, dragFile: URL?, dragImage: NSImage?, context: ActionContext, onClick: (() -> Void)?) {
        dismiss(animated: false)
        edge = context.edge

        let hosting = NSHostingView(rootView: CaptureToastView(content: content))
        let size = hosting.fittingSize
        hosting.sizingOptions = []
        let host = CaptureToastHostView(content: hosting)
        host.dragFile = dragFile
        host.dragImage = dragImage
        host.onClick = { [weak self] in
            onClick?()
            self?.dismiss()
        }
        host.onDragEnded = { [weak self] in self?.dismiss() }

        let panel = GlassPanel(content: host, configuration: Self.configuration)
        let visible = context.screen.visibleFrame
        let x = edge == .left
            ? visible.minX + Theme.toastEdgeGap
            : visible.maxX - Theme.toastEdgeGap - size.width
        let glass = CGRect(x: x, y: visible.minY + Theme.toastEdgeGap + 12, width: ceil(size.width), height: ceil(size.height))
        let final = panel.frame(forGlass: glass)
        panel.setFrame(Self.offscreen(final, edge: edge, screen: context.screen), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel

        // A timing curve that overshoots by a few points and settles: the spring of the sidebar.
        NSAnimationContext.runAnimationGroup { animation in
            animation.duration = 0.42
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 1.35, 0.55, 1)
            panel.animator().setFrame(final, display: true)
            panel.animator().alphaValue = 1
        }
        startCountdown()
    }

    private func startCountdown() {
        remaining = Self.lifetime
        let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickCountdown() }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdown = timer
    }

    /// Polls the cursor instead of tracking areas: the panel never becomes key.
    private func tickCountdown() {
        guard let panel else { return }
        let hovering = panel.glassFrame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
        if hovering { return }
        remaining -= Self.tick
        if remaining <= 0 { dismiss() }
    }

    /// `frame` moved past the screen edge it springs from.
    private static func offscreen(_ frame: NSRect, edge: ScreenEdge, screen: NSScreen?) -> NSRect {
        var hidden = frame
        let bounds = screen?.frame ?? frame
        switch edge {
        case .left: hidden.origin.x = bounds.minX - frame.width
        case .right: hidden.origin.x = bounds.maxX
        }
        return hidden
    }

    private static func openInPreview(_ url: URL) {
        let workspace = NSWorkspace.shared
        guard let preview = workspace.urlForApplication(withBundleIdentifier: "com.apple.Preview") else {
            workspace.open(url)
            return
        }
        workspace.open([url], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Log.actions.error("falha ao abrir captura: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// Takes every click on the card: a click runs `onClick`, a drag drags `dragFile`.
/// AppKit dragging rather than SwiftUI `onDrag`, which needs the panel to be key to start reliably.
private final class CaptureToastHostView: NSView, NSDraggingSource {
    var dragFile: URL?
    var dragImage: NSImage?
    var onClick: (() -> Void)?
    var onDragEnded: (() -> Void)?
    private var downLocation: NSPoint?
    private var dragging = false

    init(content: NSView) {
        super.init(frame: NSRect(origin: .zero, size: content.fittingSize))
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downLocation = event.locationInWindow
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let downLocation, let dragFile else { return }
        let dx = event.locationInWindow.x - downLocation.x
        let dy = event.locationInWindow.y - downLocation.y
        guard dx * dx + dy * dy > 16 else { return }
        dragging = true
        let item = NSDraggingItem(pasteboardWriter: dragFile as NSURL)
        let image = dragImage ?? NSWorkspace.shared.icon(forFile: dragFile.path)
        let side: CGFloat = 96
        let scale = min(side / max(image.size.width, 1), side / max(image.size.height, 1))
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let point = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { downLocation = nil }
        guard !dragging, downLocation != nil else { return }
        onClick?()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .generic] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false
        if operation != [] { onDragEnded?() }
    }
}
