#!/usr/bin/env bash
# Static/package-level smoke checks: catches things a unit test can't, like
# a broken import (the exact class of bug fixed in an earlier pass - a
# missing `import org.kde.kirigami` in main.qml) or a package that
# kpackagetool6 would actually refuse to install.
#
# Does not touch the user's real Plasma config: the trial install below
# goes into a scratch XDG_DATA_HOME, never the live one.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
UI_DIR="$REPO_ROOT/package/contents/ui"

FAILED=0

echo "== qmllint =="
QMLLINT="$(command -v qmllint-qt6 || command -v qmllint || true)"
if [[ -z "$QMLLINT" ]]; then
    echo "skip: no qmllint(-qt6) binary found on PATH"
else
    while IFS= read -r -d '' qml_file; do
        # Warnings/Info are expected here (plasmoid-injected globals like
        # `plasmoid`/`i18n` aren't visible to a standalone qmllint run) -
        # only a real "Error:" line indicates a genuine syntax problem.
        output="$("$QMLLINT" "$qml_file" 2>&1 || true)"
        if grep -q "^Error:" <<<"$output"; then
            echo "FAIL: $qml_file"
            grep "^Error:" <<<"$output"
            FAILED=1
        fi
    done < <(find "$UI_DIR" -name '*.qml' -print0)
    if [[ $FAILED -eq 0 ]]; then
        echo "ok: no qmllint errors"
    fi
fi

echo "== metadata.json is valid JSON =="
if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$REPO_ROOT/package/metadata.json"; then
    echo "ok"
else
    echo "FAIL: metadata.json is not valid JSON"
    FAILED=1
fi

echo "== config/main.xml is well-formed XML =="
if python3 -c "import xml.etree.ElementTree as ET, sys; ET.parse(sys.argv[1])" "$REPO_ROOT/package/contents/config/main.xml"; then
    echo "ok"
else
    echo "FAIL: config/main.xml is not well-formed"
    FAILED=1
fi

echo "== ConfigGeneral.qml aliases match main.xml entries =="
XML_KEYS="$(python3 -c "
import xml.etree.ElementTree as ET, sys
tree = ET.parse(sys.argv[1])
for e in tree.iter():
    if e.tag.endswith('}entry') or e.tag == 'entry':
        print(e.get('name'))
" "$REPO_ROOT/package/contents/config/main.xml" | sort)"
QML_KEYS="$(grep -oE 'cfg_[A-Za-z0-9_]+' "$UI_DIR/ConfigGeneral.qml" | sed 's/^cfg_//' | sort -u)"
MISSING=0
for key in $QML_KEYS; do
    if ! grep -qx "$key" <<<"$XML_KEYS"; then
        echo "FAIL: ConfigGeneral.qml references cfg_$key but main.xml has no matching <entry name=\"$key\">"
        MISSING=1
    fi
done
if [[ $MISSING -eq 0 ]]; then
    echo "ok"
else
    FAILED=1
fi

echo "== kpackagetool6 accepts the package (scratch install, not touching your real config) =="
KPACKAGETOOL="$(command -v kpackagetool6 || true)"
if [[ -z "$KPACKAGETOOL" ]]; then
    echo "skip: kpackagetool6 not found on PATH"
else
    SCRATCH_HOME="$(mktemp -d)"
    trap 'rm -rf "$SCRATCH_HOME"' EXIT
    if XDG_DATA_HOME="$SCRATCH_HOME/share" "$KPACKAGETOOL" -t Plasma/Applet -i "$REPO_ROOT/package" >"$SCRATCH_HOME/install.log" 2>&1; then
        echo "ok: package installs cleanly"
    else
        echo "FAIL: kpackagetool6 rejected the package"
        cat "$SCRATCH_HOME/install.log"
        FAILED=1
    fi
fi

echo
if [[ $FAILED -eq 0 ]]; then
    echo "smoke_package: all checks passed"
else
    echo "smoke_package: FAILURES ABOVE"
fi
exit $FAILED
