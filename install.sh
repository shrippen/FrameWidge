#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/shrippen/FrameWidge"
PLASMOID_ID="org.kde.plasma.framewidge"

info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*"; exit 1; }

# When piped via curl|bash, stdin is the script itself.
# Open a persistent fd to the real terminal for interactive prompts.
if [ -t 0 ]; then
    exec 3<&0
elif [ -e /dev/tty ]; then
    exec 3</dev/tty
else
    error "No interactive terminal available. Download and run the script directly instead of piping."
fi

ask() {
    local prompt="$1" var="$2"
    read -rp "$prompt" "$var" <&3
}

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
channel_choice=""
while [[ ! "$channel_choice" =~ ^[123]$ ]]; do
    ask "  Choose [1/2/3] (default: 1): " channel_choice
    channel_choice="${channel_choice:-1}"
    if [[ ! "$channel_choice" =~ ^[123]$ ]]; then
        warn "Invalid choice '$channel_choice'. Please enter 1, 2, or 3."
    fi
done

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

# --- Step 1: Download FrameWidge ---
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

# --- Step 2: Install the service (framewidged) ---
# The widget's backend: reads sensors, drives fans, power and battery as root.
# Release channels download the binary from the GitHub release; main builds it.
SERVICE_DIR="$TMPDIR/repo/service"
SERVICE_ASSET="framewidged-$(uname -m)-linux"
TOOL_DIR="/usr/local/lib/framewidge"
TOOL_URL="https://github.com/FrameworkComputer/framework-system/releases/latest/download/framework_tool"

echo ""
echo "  The FrameWidge service (framewidged) reads the sensors and drives fans,"
echo "  power and battery. It runs as a systemd service (requires root)."
if systemctl cat framework-control >/dev/null 2>&1; then
    echo ""
    echo "  framework-control is installed. framewidged replaces it, since both"
    echo "  would drive the fans: framework-control is stopped and disabled."
    echo "  Your fan, power and battery settings are taken over on first start."
fi
echo ""
ask "  Install/update the FrameWidge service? [Y/n] " answer
answer="${answer:-Y}"
if [[ "$answer" =~ ^[Yy] ]]; then
    SERVICE_BIN="$TMPDIR/framewidged"
    if [ "$DOWNLOAD_REF" != "main" ] && curl -fsSL -o "$SERVICE_BIN" "$REPO_URL/releases/download/$DOWNLOAD_REF/$SERVICE_ASSET"; then
        ok "Downloaded framewidged ($DOWNLOAD_REF)."
    elif command -v cargo >/dev/null 2>&1; then
        info "Building framewidged from source..."
        cargo build --release --locked --manifest-path "$SERVICE_DIR/Cargo.toml" --target-dir "$TMPDIR/target" \
            || error "Building framewidged failed."
        cp "$TMPDIR/target/release/framewidged" "$SERVICE_BIN"
    else
        error "No framewidged binary for $DOWNLOAD_REF ($SERVICE_ASSET) and no cargo to build it. Install Rust or choose the stable channel."
    fi

    if ! command -v framework_tool >/dev/null 2>&1 && [ ! -x "$TOOL_DIR/framework_tool" ]; then
        info "Downloading framework_tool (FrameworkComputer/framework-system)..."
        curl -fsSL -o "$TMPDIR/framework_tool" "$TOOL_URL" || error "framework_tool download failed."
        sudo install -Dm755 "$TMPDIR/framework_tool" "$TOOL_DIR/framework_tool"
    fi

    sudo install -Dm755 "$SERVICE_BIN" /usr/local/bin/framewidged
    sudo install -Dm644 "$SERVICE_DIR/data/framewidged.service" /etc/systemd/system/framewidged.service
    # The service owns a name on the system bus; polkit decides who may change settings.
    sudo install -Dm644 "$SERVICE_DIR/data/io.github.shrippen.FrameWidge.conf" /etc/dbus-1/system.d/io.github.shrippen.FrameWidge.conf
    sudo install -Dm644 "$SERVICE_DIR/data/io.github.shrippen.FrameWidge.policy" /usr/share/polkit-1/actions/io.github.shrippen.FrameWidge.policy
    sudo systemctl reload dbus 2>/dev/null || true
    sudo systemctl disable framework-control >/dev/null 2>&1 || true
    sudo systemctl daemon-reload
    sudo systemctl enable framewidged
    # Restart, not start: an update must load the new binary. Conflicts= stops framework-control.
    sudo systemctl restart framewidged
    ok "framewidged installed and running."
else
    warn "Skipping the service. The widget needs it to function."
fi

# --- Step 3: Install or update plasmoid ---
if kpackagetool6 -t Plasma/Applet -s "$PLASMOID_ID" >/dev/null 2>&1; then
    info "Updating existing plasmoid..."
    kpackagetool6 -t Plasma/Applet -u "$PACKAGE_DIR"
else
    info "Installing plasmoid..."
    kpackagetool6 -t Plasma/Applet -i "$PACKAGE_DIR"
fi

# --- Step 4: Install the app icon into the user's icon theme ---
# metadata.json's "Icon" (and windows like the widget's Configure dialog)
# resolve icon *names* through the standard XDG icon theme, which only
# looks in real theme directories - a name isn't found just because the
# plasmoid package happens to ship a file at that path. Verified with
# `kiconfinder6 framewidge` before relying on this.
ICON_SRC="$PACKAGE_DIR/contents/icons/hicolor/scalable/apps/framewidge.svg"
ICON_DEST_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
if [ -f "$ICON_SRC" ]; then
    mkdir -p "$ICON_DEST_DIR"
    cp "$ICON_SRC" "$ICON_DEST_DIR/framewidge.svg"
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
    fi
    ok "App icon installed."
fi

ok "FrameWidge installed! ($DOWNLOAD_REF)"
echo ""
echo "  Add 'FrameWidge' to your panel or system tray via"
echo "  the Plasma widget picker."
echo ""
