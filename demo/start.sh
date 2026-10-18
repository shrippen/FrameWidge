#!/usr/bin/env bash
# Opens FrameWidge in plasmoidviewer against the demo backend (demo/backend.py: the editing
# laptop of the shrippen demo world, no Framework hardware or framewidged needed).
#   demo/start.sh [de|en]
set -euo pipefail
source "$(dirname "$0")/common.sh"
start_backend
echo "demo backend on private bus ${BUS_ADDRESS}"
XDG_CONFIG_HOME="${CONFIG}" LANGUAGE="${LANG_}" LANG="${LOCALE}" \
    plasmoidviewer -a "${PACKAGE}" -f horizontal -l bottomedge -s 900x60
