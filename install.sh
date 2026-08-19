#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/shrippen/FrameWidge"
BACKEND_INSTALL="https://raw.githubusercontent.com/ozturkkl/framework-control/main/install-linux.sh"
PLASMOID_ID="org.kde.plasma.framewidge"

info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*"; exit 1; }

# --- Check prerequisites ---
command -v kpackagetool6 >/dev/null 2>&1 || error "kpackagetool6 not found. Is KDE Plasma 6 installed?"
command -v curl >/dev/null 2>&1 || error "curl is required."

# --- Release channel selection ---
echo ""
echo "  Which release channel would you like to install?"
echo ""
echo "    1) Stable  — latest stable release (recommended)"
echo "    2) Beta    — latest pre-release (newer features, may have bugs)"
echo "    3) Main    — bleeding edge from the main branch"
echo ""
read -rp "  Choose [1/2/3] (default: 1): " channel_choice
channel_choice="${channel_choice:-1}"

case "$channel_choice" in
    2)
        info "Fetching latest beta release..."
        TAG=$(curl -fsSL "https://api.github.com/repos/shrippen/FrameWidge/releases" \
            | grep -oP '"tag_name":\s*"\K[^"]+' \
            | grep -i 'beta\|alpha\|rc' \
            | head -n1) || true
        if [ -z "${TAG:-}" ]; then
            warn "No beta release found. Falling back to latest stable."
            TAG=$(curl -fsSL "https://api.github.com/repos/shrippen/FrameWidge/releases/latest" \
                | grep -oP '"tag_name":\s*"\K[^"]+')
        fi
        DOWNLOAD_REF="$TAG"
        info "Selected beta release: $TAG"
        ;;
    3)
        DOWNLOAD_REF="main"
        info "Selected: main branch (bleeding edge)"
        ;;
    *)
        info "Fetching latest stable release..."
        TAG=$(curl -fsSL "https://api.github.com/repos/shrippen/FrameWidge/releases/latest" \
            | grep -oP '"tag_name":\s*"\K[^"]+') || true
        if [ -z "${TAG:-}" ]; then
            warn "No stable release found. Falling back to main branch."
            DOWNLOAD_REF="main"
        else
            DOWNLOAD_REF="$TAG"
            info "Selected stable release: $TAG"
        fi
        ;;
esac

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

# --- Step 2: Download plasmoid ---
info "Downloading FrameWidge ($DOWNLOAD_REF)..."

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

if [ "$DOWNLOAD_REF" = "main" ]; then
    ARCHIVE_URL="$REPO_URL/archive/refs/heads/main.tar.gz"
    EXTRACTED_DIR="FrameWidge-main"
else
    ARCHIVE_URL="$REPO_URL/archive/refs/tags/$DOWNLOAD_REF.tar.gz"
    EXTRACTED_DIR="FrameWidge-${DOWNLOAD_REF#v}"
fi

curl -fsSL "$ARCHIVE_URL" | tar -xz -C "$TMPDIR" || error "Download failed."

if [ ! -d "$TMPDIR/$EXTRACTED_DIR" ]; then
    EXTRACTED_DIR=$(ls "$TMPDIR" | head -n1)
fi
mv "$TMPDIR/$EXTRACTED_DIR" "$TMPDIR/repo"

PACKAGE_DIR="$TMPDIR/repo/package"

if [ ! -f "$PACKAGE_DIR/metadata.json" ]; then
    error "Package directory not found in downloaded archive."
fi

# --- Step 3: Install or update plasmoid ---
if kpackagetool6 -t Plasma/Applet -s "$PLASMOID_ID" >/dev/null 2>&1; then
    info "Updating existing plasmoid..."
    kpackagetool6 -t Plasma/Applet -u "$PACKAGE_DIR"
else
    info "Installing plasmoid..."
    kpackagetool6 -t Plasma/Applet -i "$PACKAGE_DIR"
fi

ok "FrameWidge installed! ($DOWNLOAD_REF)"
echo ""
echo "  Add 'FrameWidge' to your panel or system tray via"
echo "  the Plasma widget picker."
echo ""
echo "  Service port: 30912 (default, configurable in widget settings)"
echo ""
