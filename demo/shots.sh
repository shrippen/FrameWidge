#!/usr/bin/env bash
# Landing-page screenshots against the demo backend, for shrippen.github.io/demo/tools/screenshots.py
# (demo/shots.json). Renders offscreen; ScreenshotRunner.qml grabs each tab into $SHOT_DIR.
set -euo pipefail
source "$(dirname "$0")/common.sh"
OUT="${SHOT_DIR:-${ROOT}/build/demo-shots}"
mkdir -p "${OUT}"
python3 - "${OUT}" "${ROOT}/demo/shots.json" > "${WORK}/plan.json" <<'PY'
import json, sys
shots = json.load(open(sys.argv[2]))["shots"]
print(json.dumps({"dir": sys.argv[1], "shots": [{"name": s["name"], "tab": s.get("tab", 0)} for s in shots]}))
PY
start_backend "${WORK}/plan.json"
cat > "${WORK}/screens.json" <<'JSON'
{ "screens": [ { "name": "shot", "x": 0, "y": 0, "width": 1920, "height": 1200,
                 "logicalDpi": 96, "logicalBaseDpi": 96, "dpr": 1 } ] }
JSON
LOG="${WORK}/viewer.log"
rc=0
XDG_CONFIG_HOME="${CONFIG}" LANGUAGE="${LANG_}" LANG="${LOCALE}" \
QT_QPA_PLATFORM="offscreen:configfile=${WORK}/screens.json" QT_QPA_PLATFORMTHEME=kde QT_SCALE_FACTOR=2 \
QT_LOGGING_TO_CONSOLE=1 QT_FORCE_STDERR_LOGGING=1 \
timeout --signal=TERM --kill-after=3 120s \
    plasmoidviewer -a "${PACKAGE}" -f horizontal -l bottomedge -s 900x60 >"${LOG}" 2>&1 || rc=$?
grep -o "FRAMEWIDGE_SCREENSHOT.*" "${LOG}" || true
if ! grep -q "FRAMEWIDGE_SCREENSHOT_DONE" "${LOG}"; then
    echo "Screenshot run did not finish (exit ${rc}). Log:"
    tail -30 "${LOG}"
    exit 1
fi
# Plasma draws the popup background; use the colour scheme's window colour instead.
BG="$(python3 - "${CONFIG}/kdeglobals" <<'PY'
import configparser, sys
c = configparser.ConfigParser(interpolation=None, strict=False)
c.read(sys.argv[1])
rgb = c.get("Colors:Window", "BackgroundNormal", fallback="40,40,40").split(",")[:3]
print("#%02x%02x%02x" % tuple(int(v) for v in rgb))
PY
)"
for f in "${OUT}"/*.png; do
    magick "${f}" -background "${BG}" -flatten "${f}"
done
