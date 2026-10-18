#!/usr/bin/env bash
# Runs every tst_*.qml under tests/qml against a throwaway mock backend on a private D-Bus:
# DBUS_SYSTEM_BUS_ADDRESS points the widget and the mock at it, the real system bus stays
# untouched.
#
# Usage: tests/run_unit_tests.sh [pattern]
#   pattern: optional glob (relative to tests/qml) to run a subset, e.g.
#            tests/run_unit_tests.sh 'tst_FanPage*.qml'
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QML_DIR="$SCRIPT_DIR/qml"
RUNTIME_DIR="$SCRIPT_DIR/.runtime"
MOCK_LOG="$RUNTIME_DIR/mock_backend.log"

# Qt 6 only: on distributions that ship both, a plain "qmltestrunner" on PATH can be the
# Qt 5 one (Arch: /usr/bin/qmltestrunner from qt5-declarative), which cannot load the Qt 6
# imports and exits 1 without printing anything.
QMLTESTRUNNER="${QMLTESTRUNNER:-}"
for candidate in /usr/lib/qt6/bin/qmltestrunner "$(command -v qmltestrunner-qt6 || true)" "$(command -v qmltestrunner || true)"; do
    [[ -n "$QMLTESTRUNNER" ]] && break
    [[ -x "$candidate" ]] && QMLTESTRUNNER="$candidate"
done
if [[ -z "$QMLTESTRUNNER" ]]; then
    echo "error: no qmltestrunner (qt6) binary found on PATH" >&2
    exit 1
fi

mkdir -p "$RUNTIME_DIR"
: > "$MOCK_LOG"

BUS_PID=""
MOCK_PID=""
cleanup() {
    for pid in "$MOCK_PID" "$BUS_PID"; do
        [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
    done
}
trap cleanup EXIT

# A bus of our own, so parallel runs and a real framewidged never meet.
exec {BUS_FD}< <(dbus-daemon --session --nofork --address="unix:tmpdir=$RUNTIME_DIR" --print-address=1 --print-pid=1)
read -r -u "$BUS_FD" BUS_ADDRESS
read -r -u "$BUS_FD" BUS_PID
export DBUS_SYSTEM_BUS_ADDRESS="$BUS_ADDRESS"

python3 "$SCRIPT_DIR/fixtures/mock_backend.py" >"$MOCK_LOG" 2>&1 &
MOCK_PID=$!
for _ in $(seq 1 50); do
    grep -q '^READY' "$MOCK_LOG" 2>/dev/null && break
    sleep 0.1
done
if ! grep -q '^READY' "$MOCK_LOG"; then
    echo "error: mock backend did not start (see $MOCK_LOG)" >&2
    exit 1
fi
echo "mock backend on private bus $BUS_ADDRESS"

PATTERN="${1:-tst_*.qml}"
FAILED=0
for test_file in "$QML_DIR"/$PATTERN; do
    [[ -e "$test_file" ]] || continue
    echo "== $(basename "$test_file") =="
    if ! "$QMLTESTRUNNER" -input "$test_file"; then
        FAILED=1
    fi
done

exit $FAILED
