#!/usr/bin/env bash
# Runs every tst_*.qml under tests/qml against a throwaway mock backend.
#
# Usage: tests/run_unit_tests.sh [pattern]
#   pattern: optional glob (relative to tests/qml) to run a subset, e.g.
#            tests/run_unit_tests.sh 'tst_FanPage*.qml'
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QML_DIR="$SCRIPT_DIR/qml"
RUNTIME_DIR="$SCRIPT_DIR/.runtime"
PORT_FILE="$RUNTIME_DIR/mock_port.txt"
MOCK_LOG="$RUNTIME_DIR/mock_backend.log"

QMLTESTRUNNER="$(command -v qmltestrunner-qt6 || command -v qmltestrunner || true)"
if [[ -z "$QMLTESTRUNNER" ]]; then
    echo "error: no qmltestrunner (qt6) binary found on PATH" >&2
    exit 1
fi

mkdir -p "$RUNTIME_DIR"
: > "$MOCK_LOG"

python3 "$SCRIPT_DIR/fixtures/mock_backend.py" >"$MOCK_LOG" 2>&1 &
MOCK_PID=$!

cleanup() {
    kill "$MOCK_PID" 2>/dev/null || true
    wait "$MOCK_PID" 2>/dev/null || true
    rm -f "$PORT_FILE"
}
trap cleanup EXIT

# Wait for the mock backend to announce its port (it binds to an ephemeral
# port so parallel test runs on the same machine never collide).
for _ in $(seq 1 50); do
    if grep -q '^PORT ' "$MOCK_LOG" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

MOCK_PORT="$(grep -m1 '^PORT ' "$MOCK_LOG" | awk '{print $2}')"
if [[ -z "$MOCK_PORT" ]]; then
    echo "error: mock backend did not start (see $MOCK_LOG)" >&2
    exit 1
fi
printf '%s' "$MOCK_PORT" > "$PORT_FILE"
echo "mock backend listening on 127.0.0.1:$MOCK_PORT"

PATTERN="${1:-tst_*.qml}"
FAILED=0
for test_file in "$QML_DIR"/$PATTERN; do
    [[ -e "$test_file" ]] || continue
    echo "== $(basename "$test_file") =="
    if ! QML_XHR_ALLOW_FILE_READ=1 "$QMLTESTRUNNER" -input "$test_file"; then
        FAILED=1
    fi
done

exit $FAILED
