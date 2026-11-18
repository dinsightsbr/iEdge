# Security Policy

## Supported versions

iEdge is young; only the latest release receives security fixes.

| Version | Supported |
| --- | --- |
| 0.1.x | ✅ |

## Reporting a vulnerability

**Please don't open a public issue for security problems.** Report them privately through GitHub:
go to the repository's **Security** tab and click **Report a vulnerability**
([direct link](https://github.com/dinsightsbr/iEdge/security/advisories/new)).

Please include the iEdge and macOS versions, what an attacker could do, and the steps to
reproduce. Reports in English or Portuguese are welcome.

We'll acknowledge the report as soon as we can, keep you posted while we investigate, and credit
you in the advisory and the changelog unless you prefer otherwise. Please give us a reasonable
time to release a fix before disclosing the issue.

## Scope

iEdge runs locally, makes no network requests, and asks only for Screen Recording and
Accessibility. The areas where a vulnerability would matter most are:

- **Clipboard history.** Leaking clipboard contents: recording copies that should be ignored
  (concealed or transient pasteboard types, excluded apps), writing them anywhere other than
  `~/Library/Application Support/iEdge/`, keeping them after they were cleared or after quitting
  with history persistence off, or exposing them in logs.
- **Screenshots.** Captures saved somewhere unexpected, captures of a different display or window
  than the one requested, or captures that include iEdge's own panels.
- **Shortcut commands.** The *Command* and *Shortcut* item types run `/bin/zsh -lc` and
  `shortcuts run` by design, with the text the user typed. Running a command is the feature;
  a vulnerability would be a way for *someone other than the user* to add, change or trigger
  one (for example through a crafted `settings.json`, a link, or another app), or a way for
  other input (pasteboard, file names, URLs) to reach a shell.
- **Automatic paste.** Sending ⌘V to an app other than the frontmost one, or pasting without the
  user picking an entry.

Out of scope: the fact that the app is signed ad hoc and not notarized (a known limitation of the
current releases), and issues that require an attacker who already controls your user account.
