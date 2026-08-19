#!/usr/bin/env bash
set -euo pipefail

PLASMOID_ID="org.kde.plasma.framewidge"

info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }

info "Removing Framework Control plasmoid..."

if kpackagetool6 -t Plasma/Applet -s "$PLASMOID_ID" >/dev/null 2>&1; then
    kpackagetool6 -t Plasma/Applet -r "$PLASMOID_ID"
    ok "Plasmoid removed."
else
    warn "Plasmoid was not installed."
fi

echo ""
echo "  Note: The framework-control backend service was NOT removed."
echo "  To remove it, run:"
echo "    curl -fsSL https://raw.githubusercontent.com/ozturkkl/framework-control/main/uninstall-linux.sh | sudo bash"
echo ""
