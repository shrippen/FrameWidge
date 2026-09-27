# Shared by demo/start.sh and demo/shots.sh: the demo backend on a free port, a package copy
# that talks to it, and a scratch config home.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/framewidge-demo-XXXXXX")"
BACKEND_PID=""
cleanup() { [[ -n "${BACKEND_PID}" ]] && kill "${BACKEND_PID}" 2>/dev/null; rm -rf "${WORK}"; }
trap cleanup EXIT
CONFIG="${WORK}/config"
mkdir -p "${CONFIG}"
cp -p "${XDG_CONFIG_HOME:-${HOME}/.config}/kdeglobals" "${CONFIG}/" 2>/dev/null || true

start_backend() {   # [plan file]
    python3 -u "${ROOT}/demo/backend.py" 0 "$@" > "${WORK}/backend.out" 2>&1 &
    BACKEND_PID=$!
    for _ in $(seq 1 50); do
        PORT="$(sed -n 's/^PORT //p' "${WORK}/backend.out")"
        [[ -n "${PORT}" ]] && break
        sleep 0.1
    done
    [[ -n "${PORT}" ]] || { echo "demo backend did not start"; cat "${WORK}/backend.out"; exit 1; }
    # A copy of the package whose default servicePort is the demo port: plasmoidviewer drops
    # preset applet settings, and the installed widget and the real service stay untouched.
    PACKAGE="${WORK}/package"
    cp -a "${ROOT}/package" "${PACKAGE}"
    python3 - "${PACKAGE}/contents/config/main.xml" "${PORT}" <<'PY'
import re, sys
path, port = sys.argv[1], sys.argv[2]
text = open(path).read()
text = re.sub(r'(<entry name="servicePort" type="Int">.*?<default>)\d+(</default>)', r'\g<1>' + port + r'\g<2>', text, flags=re.S)
open(path, "w").write(text)
PY
    grep -q "<default>${PORT}</default>" "${PACKAGE}/contents/config/main.xml" || { echo "could not set the demo port"; exit 1; }
}

LANG_="${1:-${DEMO_LANG:-de}}"
case "${LANG_}" in de) LOCALE=de_DE.UTF-8 ;; *) LOCALE=en_GB.UTF-8 ;; esac
# Translations of a package started from a path: offer them from a data dir.
if [[ -d "${ROOT}/package/contents/locale" ]]; then
    mkdir -p "${WORK}/data/locale"
    cp -r "${ROOT}/package/contents/locale/." "${WORK}/data/locale/"
    export XDG_DATA_DIRS="${WORK}/data:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
fi
