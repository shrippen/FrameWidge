# Shared by demo/start.sh and demo/shots.sh: the demo backend on a private D-Bus that stands in
# for the system bus (DBUS_SYSTEM_BUS_ADDRESS, exported for plasmoidviewer too), a package copy
# with the screenshot runner, and a scratch config home. The real system bus and a running
# framewidged are not touched.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/framewidge-demo-XXXXXX")"
BACKEND_PID=""
BUS_PID=""
cleanup() {
    for pid in "${BACKEND_PID}" "${BUS_PID}"; do
        [[ -n "${pid}" ]] && kill "${pid}" 2>/dev/null
    done
    rm -rf "${WORK}"
}
trap cleanup EXIT
CONFIG="${WORK}/config"
mkdir -p "${CONFIG}"
cp -p "${XDG_CONFIG_HOME:-${HOME}/.config}/kdeglobals" "${CONFIG}/" 2>/dev/null || true

start_backend() {   # [plan file]
    exec {BUS_FD}< <(dbus-daemon --session --nofork --address="unix:tmpdir=${WORK}" --print-address=1 --print-pid=1)
    read -r -u "${BUS_FD}" BUS_ADDRESS
    read -r -u "${BUS_FD}" BUS_PID
    export DBUS_SYSTEM_BUS_ADDRESS="${BUS_ADDRESS}"

    python3 -u "${ROOT}/demo/backend.py" "$@" > "${WORK}/backend.out" 2>&1 &
    BACKEND_PID=$!
    for _ in $(seq 1 50); do
        grep -q "^READY" "${WORK}/backend.out" && break
        sleep 0.1
    done
    grep -q "^READY" "${WORK}/backend.out" || { echo "demo backend did not start"; cat "${WORK}/backend.out"; exit 1; }
    # A copy of the package, so the installed widget stays untouched.
    PACKAGE="${WORK}/package"
    cp -a "${ROOT}/package" "${PACKAGE}"
    # The screenshot runner is internal and only exists in this copy.
    cp "${ROOT}/demo/ScreenshotRunner.qml" "${PACKAGE}/contents/ui/"
    python3 - "${PACKAGE}/contents/ui/main.qml" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
anchor = "    fullRepresentation: FullRepresentation {}\n"
assert anchor in text, "main.qml changed: cannot add the screenshot runner"
open(path, "w").write(text.replace(anchor, anchor + "\n    ScreenshotRunner {\n        plasmoidRoot: root\n    }\n", 1))
PY
}

LANG_="${1:-${DEMO_LANG:-de}}"
case "${LANG_}" in de) LOCALE=de_DE.UTF-8 ;; *) LOCALE=en_GB.UTF-8 ;; esac
# Translations of a package started from a path: offer them from a data dir.
if [[ -d "${ROOT}/package/contents/locale" ]]; then
    mkdir -p "${WORK}/data/locale"
    cp -r "${ROOT}/package/contents/locale/." "${WORK}/data/locale/"
    export XDG_DATA_DIRS="${WORK}/data:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
fi
