#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/arian/framework-control-plasmoid"
BACKEND_INSTALL="https://raw.githubusercontent.com/ozturkkl/framework-control/main/install-linux.sh"
PLASMOID_ID="org.kde.plasma.framewidge"

info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*"; exit 1; }

# --- Check prerequisites ---
command -v kpackagetool6 >/dev/null 2>&1 || error "kpackagetool6 not found. Is KDE Plasma 6 installed?"
command -v curl >/dev/null 2>&1 || error "curl is required."

# --- Step 1: Install backend (framework-control service) ---
info "Checking framework-control backend service..."

if systemctl is-active --quiet framework-control 2>/dev/null; then
    ok "framework-control service is already running."
else
    info "framework-control service is not running."
    echo ""
    echo "  The backend service is required. It manages fans, power, battery"
    echo "  and runs as a systemd service (requires root)."
    echo ""
    read -rp "  Install/update the framework-control backend? [Y/n] " answer
    answer="${answer:-Y}"
    if [[ "$answer" =~ ^[Yy] ]]; then
        info "Installing framework-control backend..."
        curl -fsSL "$BACKEND_INSTALL" | sudo bash
        ok "Backend installed."
    else
        warn "Skipping backend install. The plasmoid needs the service to function."
    fi
fi

# --- Step 2: Install plasmoid ---
info "Installing Framework Control plasmoid..."

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

if command -v git >/dev/null 2>&1; then
    git clone --depth 1 "$REPO_URL.git" "$TMPDIR/repo" 2>/dev/null || {
        warn "git clone failed, trying tarball download..."
        curl -fsSL "$REPO_URL/archive/refs/heads/main.tar.gz" | tar -xz -C "$TMPDIR"
        mv "$TMPDIR"/framework-control-plasmoid-main "$TMPDIR/repo"
    }
else
    curl -fsSL "$REPO_URL/archive/refs/heads/main.tar.gz" | tar -xz -C "$TMPDIR"
    mv "$TMPDIR"/framework-control-plasmoid-main "$TMPDIR/repo"
fi

PACKAGE_DIR="$TMPDIR/repo/package"

if [ ! -f "$PACKAGE_DIR/metadata.json" ]; then
    error "Package directory not found in downloaded repo."
fi

# Install or update
if kpackagetool6 -t Plasma/Applet -s "$PLASMOID_ID" >/dev/null 2>&1; then
    info "Updating existing plasmoid..."
    kpackagetool6 -t Plasma/Applet -u "$PACKAGE_DIR"
else
    info "Installing plasmoid..."
    kpackagetool6 -t Plasma/Applet -i "$PACKAGE_DIR"
fi

ok "Plasmoid installed!"
echo ""
echo "  Add 'FrameWidge' to your panel or system tray via"
echo "  the Plasma widget picker."
echo ""
echo "  Service port: 30912 (default, configurable in widget settings)"
echo ""
