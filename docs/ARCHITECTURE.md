# Architecture

iEdge is a single SwiftPM executable target (`Sources/iEdge`) plus a test target
(`Tests/iEdgeTests`). There is no Xcode project and no third-party dependency. The app is a
menu-bar accessory (`LSUIElement`, `.accessory` activation policy): no Dock icon, no main window.

This document is the map for contributors. The original design spec, in Portuguese, is
[SPEC.md](SPEC.md); it has the exact numbers (timings, sizes, springs) and is still the reference
for behaviour.

## Modules

| Folder | Responsibility | Key types |
| --- | --- | --- |
| `App/` | Entry point, wiring, development flags | `main.swift`, `AppDelegate`, `LaunchOptions` (pure parser), `BackdropWindow` |
| `Core/` | Shared building blocks | `GlassPanel` (borderless glass window), `Theme`, `AppPaths`, `Log`, `Snapshot` / `SnapshotSupport` |
| `Models/` | Plain `Codable` values | `AppSettings`, `SidebarItem`, `ActionKind`, `ClipboardEntry`, `ScreenEdge`, `ActionContext`, `SettingsTab` |
| `Stores/` | Settings persistence | `SettingsStore` |
| `Edge/` | When to open the sidebar | `EdgeMonitor`, `EdgeGeometry` and the trigger state machine (pure), `EdgeDockSide` |
| `Sidebar/` | The sidebar and its flyout | `SidebarController`, `SidebarPanel`, `SidebarView`, `Magnification` (pure), `ClipboardFlyout` |
| `Actions/` | What items do | `ActionRunner`, `ScreenshotService` (+ pure `Screenshot` helpers), `CustomActions`, `ActionProcess`, `CaptureToast` |
| `Clipboard/` | Clipboard history | `ClipboardMonitor`, `ClipboardHistory` (pure), `ClipboardStore`, `ClipboardImageFiles`, `ClipboardListView` |
| `MenuBar/` | Status item and the Settings panel | `StatusItemController` |
| `Settings/` | Settings UI | `SettingsRootView`, one view per tab, `SettingsItemEditing` (pure), `PermissionCenter`, `LoginItem` |

`Snapshots+Sidebar.swift`, `Snapshots+Clipboard.swift` and `Snapshots+Settings.swift` each add
their views to the `--snapshot` catalog, so every area owns its own previews.

## Wiring and contracts

`AppDelegate` builds the object graph once, in this order, and each object only knows the ones
before it:

```
SettingsStore ─▶ ClipboardStore ─▶ ActionRunner ─▶ SidebarController ─▶ EdgeMonitor
                                                          ▲                  │ onTrigger(edge, screen, y)
                                                          └──────────────────┘
                                   StatusItemController (Settings panel, quick menu)
```

The contracts between the pieces are small and stable:

```swift
@MainActor final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings          // every change is saved to settings.json (debounced)
    init(demo: Bool)                              // demo: never reads or writes the disk
}

@MainActor protocol ActionPerforming: AnyObject {
    func perform(_ item: SidebarItem, context: ActionContext)   // called with the sidebar already closed
}

struct ActionContext { var edge: ScreenEdge; var screen: NSScreen; var anchor: CGRect }  // anchor = the tile on screen

@MainActor final class ClipboardStore: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry]
    func start(); func stop()
    func copy(_ entry: ClipboardEntry, paste: Bool)
    func togglePin(_ entry: ClipboardEntry); func remove(_ entry: ClipboardEntry); func clear()
}

@MainActor final class SidebarController {
    var isVisible: Bool { get }
    func show(edge: ScreenEdge, on screen: NSScreen, atY y: CGFloat)
    func hide(animated: Bool)
}

@MainActor final class EdgeMonitor {
    init(settings: SettingsStore, isSidebarVisible: @escaping () -> Bool)
    var onTrigger: ((ScreenEdge, NSScreen, CGFloat) -> Void)?
    func start(); func stop()
}
```

Everything that touches UI is `@MainActor`. `main.swift` enters the main actor with
`MainActor.assumeIsolated`. The package builds in the Swift 5 language mode.

## Flow: edge → sidebar → action

1. **Edge.** `EdgeMonitor` installs a global and a local `NSEvent` monitor for `mouseMoved`
   (mouse events need no Accessibility permission). For each event it asks `EdgeGeometry` which
   edge, if any, the cursor is on: only a *real* edge counts (not one shared with another
   display), not the top and bottom corners, not the Dock's edge unless forced, not a disabled
   edge, not while paused. The pure trigger state machine then decides: it fires after the cursor
   has rested `dwellMs`, or once the movement pushing into the edge adds up to `pushDistance`; it
   never fires with a mouse button down, and after firing it waits for the cursor to leave the
   edge. The only timer is the dwell timer, which exists only while the cursor sits on an edge.
2. **Sidebar.** `onTrigger` calls `SidebarController.show(edge:on:atY:)`. The controller sizes a
   `SidebarPanel` for the largest magnified stack, places the capsule 8 pt from the edge at the
   cursor's height (clamped to the visible frame) and springs it in. While the sidebar is visible,
   and only then, a display link reads `NSEvent.mouseLocation` every frame, feeds it to
   `Magnification`, and publishes the tile layout to `SidebarView`. The controller closes the
   sidebar when the cursor moves more than 40 pt away, on a click outside, or from the menu.
3. **Clipboard flyout.** Resting on the clipboard tile (or clicking it) opens `ClipboardFlyout`, a
   child window of the sidebar that embeds `ClipboardListView`. Picking an entry calls
   `ClipboardStore.copy(_:paste:)`.
4. **Action.** Clicking any other tile closes the sidebar first and then calls
   `ActionRunner.perform(_:context:)`, so screenshots never contain it. `ScreenshotService` runs
   `/usr/sbin/screencapture` and shows the `CaptureToast` preview; `CustomActions` opens apps and
   URLs through `NSWorkspace` or runs `shortcuts run` / `/bin/zsh -lc` through `ActionProcess`.
   Every process is started with an argument array, never by building a shell string, and runs
   off the main thread. Failures become a toast, never a modal alert.

## Data on disk

All files live in `~/Library/Application Support/iEdge/` (`AppPaths`), created on the first save.
Paths are computed without touching the disk, so `--demo` creates nothing.

| File | Owner | Notes |
| --- | --- | --- |
| `settings.json` | `SettingsStore` | `AppSettings`, saved shortly after each change. Decoding is tolerant: missing keys keep their defaults, numbers are clamped, and an unknown action type from a newer version drops only that item. |
| `clipboard.json` | `ClipboardStore` | The history, only when `clipboard.persist` is on. |
| `clipboard/<id>.png`, `clipboard/<id>-thumb.png` | `ClipboardImageFiles` | Copied images and their list thumbnails, written with ImageIO off the main thread. Deleted with their entry; deleted on quit when history isn't persisted. |

An unreadable `settings.json` or `clipboard.json` is kept as `*.corrompido` and the app starts
from the defaults. `ActionKind` is encoded as a flat object with a `type` field
(`{"type":"openURL","url":"…"}`) so the file stays readable.

The clipboard rules live in `ClipboardHistory`, a value type with no I/O: identical content moves
to the top instead of duplicating, the size limit never evicts pinned entries, clearing keeps the
pinned ones. `ClipboardMonitor` polls `NSPasteboard.general.changeCount` every 0.5 s (there is no
change notification) and drops concealed/transient/auto-generated types, excluded apps, oversized
content and iEdge's own writes before anything reaches the history. Copied content is never
logged.

## Design decisions

- **Non-activating panels.** The sidebar, flyout and toast are `NSPanel`s with
  `.nonactivatingPanel` that never become key, so the app you were using stays frontmost:
  ⌘V lands in it and window captures target it. Their content views accept the first mouse, so a
  tile reacts on the first click without activating iEdge. Only the Settings panel can become key
  (for its text fields).
- **A display link only while the sidebar is open.** Nothing runs at 60 Hz while the sidebar is
  closed: edge detection is event-driven, and the magnifier's display link is created on show and
  invalidated on hide. iEdge should cost nothing when you're not using it.
- **Pure core, thin AppKit shell.** Edge geometry and the trigger, the magnifier, the clipboard
  history, item editing, settings decoding, capture arguments and file names, and the launch flags
  are pure Swift with no windows involved. That's where the tests are, and it keeps the AppKit
  classes small.
- **Glass.** `GlassPanel` uses `NSGlassEffectView` (Liquid Glass) on macOS 26 and
  `NSVisualEffectView` with the `.popover` material before that; SwiftUI views use `glassEffect`
  under the same `#available` check. The window is larger than the glass by fixed margins so the
  glass's own shadow and the magnified tiles fade out inside the window instead of being cut at
  its square edge; the window shadow is off. The glass and the content are siblings pinned with
  explicit constraints, which avoids an Auto Layout feedback loop with `NSGlassEffectView` on
  resize. The sidebar panel draws its capsule itself (`drawsGlass: false`), since the capsule
  grows with the magnifier inside a window of fixed size.
- **The sidebar closes before acting.** Every action except the clipboard runs after the sidebar
  is gone, so captures never include it and focus is where you left it.
- **Processes without a shell.** `screencapture`, `shortcuts` and the user's command are all
  started with argument arrays. A user command is deliberately run with `/bin/zsh -lc` because
  running a command is the feature; nothing else interpolates strings into a shell.

## Testing

```bash
swift test
```

| Test file | Covers |
| --- | --- |
| `EdgeGeometryTests` | real edge vs. neighbouring display, corners, Dock side, negative origins, the dwell/push trigger and re-arming |
| `MagnificationTests` | the Gaussian scale, no overlap, selected item, stack height, capsule that fits the window |
| `SidebarAnimationTests` | the spring damping behind the ~6 pt overshoot |
| `ClipboardHistoryTests` | de-duplication, the limit, pinned entries, clearing; ignored pasteboard types and excluded apps; the store's files (persistence, orphan images, unreadable file backup) |
| `ScreenshotTests` | `screencapture` arguments, file names, display index, folder choice; argument arrays for shortcuts and commands; link targets; process timeouts |
| `AppSettingsTests` | round trip, old JSON without new keys, clamping, unknown action types, `SettingsStore` save/reload and demo mode writing nothing |
| `SettingsEditingTests` | adding, editing, moving and restoring items; validation of the "Add shortcut" form |
| `LaunchOptionsTests` | development flags (including `--backdrop`) and the snapshot catalog |

For anything visual, use the development flags (see the README): `--snapshot` renders a view to a
PNG without opening a window, and the real app with `--demo --backdrop --show … --pin
--frame-file …` can be screenshotted with `screencapture -R` on a clean background. CI runs
`swift build` and `swift test` on a macOS 26 runner for every push and pull request to `main`.
