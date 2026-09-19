# FrameWidge

> **100% vibe coded.** All code, the landing page and this README were AI-generated. Use at your own risk. Report bugs.

KDE Plasma 6 tray widget for [Framework Laptops](https://frame.work): fan control, power management, battery and sensor telemetry.

> **Not a fork.** Independent frontend for the REST API of [ozturkkl/framework-control](https://github.com/ozturkkl/framework-control) by Kemal Ozturk.

## Features

- **Fan control:** auto, manual duty, drag-and-drop curve editor, hysteresis, rate limiting, per-fan overrides (Framework 16), calibration wizard
- **Sensors:** live temperature graphs, sensor selection, configurable time window
- **Power:** AC/battery profiles, EPP, governor, frequency limits, TDP and thermal controls (capability-driven)
- **Battery:** charge/discharge wattage, health, cycles, charge limit (25–100%), rate limit with SoC threshold
- **Tray:** temperature/RPM/SoC overlay, tooltip with live stats
- **Offline detection:** setup guide when the backend is missing or stopped

## Requirements

- Framework Laptop 13 or 16 (AMD/Intel)
- KDE Plasma 6 (Wayland or X11)
- Linux with systemd
- [framework-control](https://github.com/ozturkkl/framework-control/blob/main/LINUX_INSTALL.MD) backend

## Install

Installs backend and widget:

```bash
curl -fsSL https://raw.githubusercontent.com/shrippen/FrameWidge/main/install.sh | bash
```

Then add **FrameWidge** via the Plasma widget picker.

### Manual install

1. Backend:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/ozturkkl/framework-control/main/install-linux.sh | sudo bash
   ```

2. Plasmoid:
   ```bash
   git clone https://github.com/shrippen/FrameWidge.git
   cd FrameWidge
   kpackagetool6 -t Plasma/Applet -i package/
   ```

3. App icon (optional; the Configure dialog falls back to a generic icon without it):
   ```bash
   mkdir -p ~/.local/share/icons/hicolor/scalable/apps
   cp package/contents/icons/hicolor/scalable/apps/framewidge.svg ~/.local/share/icons/hicolor/scalable/apps/
   ```

### Update

```bash
cd FrameWidge && git pull
kpackagetool6 -t Plasma/Applet -u package/
```

## Uninstall

```bash
# Plasmoid
kpackagetool6 -t Plasma/Applet -r org.kde.plasma.framewidge

# Backend (optional)
curl -fsSL https://raw.githubusercontent.com/ozturkkl/framework-control/main/uninstall-linux.sh | sudo bash
```

## Configuration

Right-click the widget → Configure.

| Setting | Default | Description |
|---------|---------|-------------|
| Service port | `30912` | framework-control port (AUR default) |
| Poll interval | `2000` ms | Health check and data polling interval |
| Tray display | `temp` | Compact icon content: `temp`, `rpm`, `soc`, `icon` |

## Architecture

```
┌──────────────────┐       HTTP (127.0.0.1)       ┌─────────────────────────┐
│  Plasma Widget   │ ──────────────────────────── │  framework-control      │
│  (QML)           │    GET/POST /api/*            │  service (Rust/systemd) │
│                  │                               │  → framework_tool CLI   │
└──────────────────┘                               └─────────────────────────┘
```

Pure QML, no compilation. Talks to `http://127.0.0.1:<port>/api/` via `XMLHttpRequest`.

## License

MIT, see [LICENSE](LICENSE). Based on [framework-control](https://github.com/ozturkkl/framework-control) by Kemal Ozturk (MIT).
