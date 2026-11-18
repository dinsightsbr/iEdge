# Changelog

All notable changes to iEdge are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-18

First public release.

### Added

- A sidebar that springs out of the left or right screen edge when the cursor rests on it or
  pushes against it. It ignores the corners, a held mouse button, the Dock's edge, edges shared
  with another display and the paused state.
- A Dock-like vertical magnifier with the item's name beside it and a light trackpad tap when the
  selection changes.
- Screenshots of the full screen, an area or a window through `screencapture`, saved to a file,
  the clipboard or both, with a preview that can be clicked or dragged; a button for the
  Screenshot app.
- Clipboard history for text, images, files and links, with pinning, automatic paste, excluded
  apps and filters for concealed and transient pasteboard types.
- Custom shortcuts: open an app, open a link or file, run a Shortcuts shortcut, run a shell command.
- Settings in a glass panel under the menu-bar icon (Items, Edges, Screenshots, Clipboard,
  General) and a quick menu on right click.
- Liquid Glass on macOS 26 and the system material on macOS 14–15.
- Development flags for inspecting the app: `--demo`, `--show`, `--pin`, `--hover`, `--flyout`,
  `--settings`, `--frame-file`, `--snapshot`, `--scheme` and `--backdrop`.

[Unreleased]: https://github.com/dinsightsbr/iEdge/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/dinsightsbr/iEdge/releases/tag/v0.1.0
