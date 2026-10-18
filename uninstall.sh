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

ICON_FILE="$HOME/.local/share/icons/hicolor/scalable/apps/framewidge.svg"
if [ -f "$ICON_FILE" ]; then
    rm -f "$ICON_FILE"
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
    fi
    ok "App icon removed."
fi

if systemctl cat framewidged >/dev/null 2>&1; then
    read -rp "  Remove the FrameWidge service (framewidged) too? [y/N] " answer </dev/tty || answer=""
    if [[ "${answer:-N}" =~ ^[Yy] ]]; then
        # Stopping runs ExecStopPost, which hands the fans back to the EC.
        sudo systemctl disable --now framewidged
        sudo rm -f /etc/systemd/system/framewidged.service /usr/local/bin/framewidged
        sudo rm -rf /var/lib/framewidged /usr/local/lib/framewidge
        sudo systemctl daemon-reload
        ok "Service removed."
    else
        warn "Service kept. Remove it later with: sudo systemctl disable --now framewidged"
    fi
fi
