#!/usr/bin/env bash
# The one smoke test that exercises the plasmoid the way a user actually
# would: install it and load it inside a real Plasma host process
# (plasmawindowed), the only thing that provides `plasmoid.configuration`
# and `i18n` for real - a QML unit test cannot fake either (see
# tests/qml/tst_*.qml comments). This is exactly the class of regression
# an earlier bug slipped through: main.qml referenced Kirigami.Units
# without importing Kirigami, which only breaks once something actually
# tries to *display* the widget.
#
# Everything is sandboxed into a scratch XDG_DATA_HOME so this never
# touches the user's real installed widgets or Plasma config, and it never
# talks to a real Framework laptop backend - just whatever (if anything)
# is already listening on the widget's configured default port, so it
# exercises the offline path just as validly as the online one.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APPLET_ID="org.kde.plasma.framewidge"

PLASMAWINDOWED="$(command -v plasmawindowed || true)"
KPACKAGETOOL="$(command -v kpackagetool6 || true)"
if [[ -z "$PLASMAWINDOWED" || -z "$KPACKAGETOOL" ]]; then
    echo "skip: plasmawindowed and/or kpackagetool6 not found on PATH"
    exit 0
fi

SCRATCH_HOME="$(mktemp -d)"
cleanup() { rm -rf "$SCRATCH_HOME"; }
trap cleanup EXIT

export XDG_DATA_HOME="$SCRATCH_HOME/share"
export XDG_CONFIG_HOME="$SCRATCH_HOME/config"
export XDG_CACHE_HOME="$SCRATCH_HOME/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"

echo "== installing into scratch XDG_DATA_HOME =="
"$KPACKAGETOOL" -t Plasma/Applet -i "$REPO_ROOT/package"

echo "== launching plasmawindowed (offscreen, ${RUN_SECONDS:-6}s) =="
LOG="$SCRATCH_HOME/plasmawindowed.log"
set +e
QT_QPA_PLATFORM=offscreen timeout "${RUN_SECONDS:-6}" "$PLASMAWINDOWED" "$APPLET_ID" >"$LOG" 2>&1
STATUS=$?
set -e

echo "--- plasmawindowed output ---"
cat "$LOG"
echo "-----------------------------"

# timeout's exit code 124 just means "we killed it after N seconds because
# it's a GUI app that runs forever" - that's the success case here: it
# means the widget stayed alive without crashing for the whole window.
if [[ $STATUS -ne 0 && $STATUS -ne 124 ]]; then
    echo "FAIL: plasmawindowed exited with unexpected status $STATUS"
    exit 1
fi

# plasmawindowed is a real Plasma host, so unlike the QML unit tests,
# `i18n`/`plasmoid.configuration` genuinely exist here - any ReferenceError,
# TypeError, or missing-module warning below is a real regression, not a
# harness artifact.
if grep -Ei 'ReferenceError|TypeError|is not a type|module .* is not installed|Cannot assign to non-existent property' "$LOG"; then
    echo "FAIL: plasmawindowed logged real QML errors (see above)"
    exit 1
fi

echo "smoke_plasmawindowed: widget loaded and ran without QML errors"
