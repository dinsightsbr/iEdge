# Contributing to iEdge

Thanks for your interest in iEdge! Bug reports, ideas, fixes and translations are all welcome.
You can write in **English or Portuguese**.

By participating you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to help

- **Report a bug** with the [bug report form](https://github.com/dinsightsbr/iEdge/issues/new?template=bug_report.yml).
  Include your macOS and iEdge versions, your display setup and the steps to reproduce.
- **Suggest a feature** with the [feature request form](https://github.com/dinsightsbr/iEdge/issues/new?template=feature_request.yml).
  For anything large, please open an issue to discuss it before writing code.
- **Localize the app.** The interface is in Brazilian Portuguese only. Moving the strings to a
  String Catalog and adding English (and other languages) is one of the most useful contributions
  right now; open an issue first so we can agree on the approach.
- **Security issues** go through private reporting, not public issues: see [SECURITY.md](SECURITY.md).

## Setting up

You need a Mac with **Xcode 26 or later** (the code uses Liquid Glass from the macOS 26 SDK). There
are no dependencies to install.

```bash
git clone https://github.com/dinsightsbr/iEdge.git
cd iEdge
swift build
swift test
bash scripts/run-dev.sh --demo     # run with sample data, nothing read from or written to disk
```

`bash scripts/build-app.sh` builds `build/iEdge.app`. Permissions (Screen Recording,
Accessibility) and Open at login only behave properly from the `.app`.

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the module map; [docs/SPEC.md](docs/SPEC.md)
(in Portuguese) has the exact behaviour, timings and sizes.

## Making a change

1. Fork the repository and create a branch from `main`.
2. Keep the change focused: one fix or feature per pull request.
3. Make sure `swift build` has **no warnings** and `swift test` passes.
4. Add or update tests for logic. Edge geometry, the magnifier, clipboard history, settings
   decoding, capture arguments and launch flags are pure functions on purpose; keep new logic
   testable the same way, out of the AppKit classes.
5. For visual changes, attach before/after screenshots. Take them with the development flags so
   they show nothing of your own screen, for example:

   ```bash
   .build/debug/iEdge --demo --backdrop --show left --pin --flyout --frame-file /tmp/f.txt &
   sleep 4 && cat /tmp/f.txt          # x y w h per panel
   screencapture -x -R<x>,<y>,<w>,<h> shot.png
   ```

   or render a single view with `--snapshot <name> --out shot.png` (`--snapshot list` shows the names).
6. Update `README.md`, `README.pt-BR.md` and `CHANGELOG.md` (under **Unreleased**) when the change
   is visible to users.
7. Open the pull request and fill in the template.

## Code style

- Swift 5 language mode, `swift-tools-version:5.9`, deployment target macOS 14. Anything newer goes
  behind `#available` with a fallback.
- UI types are `@MainActor`. No force-unwrapping of external data (pasteboard, JSON, processes).
- No `print` in app code: use the `Log` loggers (`Logger` with subsystem `br.dinsights.iedge`), and
  never log clipboard contents.
- External processes are started with argument arrays, never by building a shell string.
- Code and comments are in English; comments explain *why*, not *what*. UI strings are in
  Portuguese for now.
- Four-space indentation (see `.editorconfig`).
- Keep the app dependency-free and offline. A change that adds a dependency or a network request
  needs a strong reason and a discussion first.

## Commit messages

Short imperative subject line in English (for example `Fix flyout position on a second display`),
with a body explaining what and why when it isn't obvious.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
