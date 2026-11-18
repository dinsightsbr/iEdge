#!/usr/bin/env bash
# Runs the app straight from SwiftPM (debug), passing any dev flags through, e.g.
#   scripts/run-dev.sh --demo --show left --pin
# Permissions (Screen Recording, Accessibility) and "abrir ao iniciar sessão" behave properly
# only from the .app bundle (scripts/build-app.sh); everything else works here.
set -euo pipefail
cd "$(dirname "$0")/.."
swift run iEdge "$@"
