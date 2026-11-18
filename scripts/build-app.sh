#!/usr/bin/env bash
# Builds the SwiftPM executable and wraps it in build/iEdge.app (menu-bar app, no Dock icon).
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/iEdge.app"

echo "▶ swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/iEdge"
if [[ ! -x "$BIN" ]]; then
  echo "binário não encontrado em $BIN" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/iEdge"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature keeps a stable identity between builds, so the Screen Recording and
# Accessibility grants are not asked again on every run.
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "aviso: codesign ad-hoc falhou (segue sem assinatura)"
fi

echo
echo "✔ $APP pronto"
echo "  abrir:     open \"$APP\""
echo "  instalar:  rm -rf /Applications/iEdge.app && cp -R \"$APP\" /Applications/"
