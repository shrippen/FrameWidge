# FrameWidge

A native **KDE Plasma 6** system tray widget for [Framework Laptops](https://frame.work), providing fan control, power management, battery monitoring, and sensor telemetry — all from your panel.

> **This is not a fork.** This project is an independent Plasma widget that talks to the REST API of [ozturkkl/framework-control](https://github.com/ozturkkl/framework-control). The backend service is developed and maintained by Kemal Ozturk. FrameWidge simply provides a native KDE frontend.

> **100% vibe coded.** This entire project — every QML file, every script, the landing page, this README — was generated through AI-assisted development. No line was written by hand. Use at your own risk, and please report bugs!

## Features

- **Fan Control** — Auto, manual duty slider, custom curve editor with drag-and-drop points, hysteresis, rate limiting, per-fan overrides (Framework 16), and calibration wizard
- **Sensors** — Live temperature graphs with history, sensor selection, and configurable time window
- **Power** — AC/Battery profiles, EPP, governor, frequency limits, TDP and thermal controls (capability-driven)
- **Battery** — Live charge/discharge wattage, health, cycles, charge limit (25–100%), rate limit with SoC threshold
- **System Tray** — Compact icon with temperature/RPM/SoC overlay, tooltip with live stats
- **Offline Detection** — Friendly setup guide when the backend service is not installed or running

## Requirements

- **Framework Laptop** (13 or 16, AMD/Intel)
- **KDE Plasma 6** (Wayland or X11)
- **Linux** with systemd (Arch, Fedora, NixOS, etc.)
- **framework-control** backend service ([install guide](https://github.com/ozturkkl/framework-control/blob/main/LINUX_INSTALL.MD))

## Install

One command installs both the backend and the widget:

```bash
curl -fsSL https://raw.githubusercontent.com/shrippen/FrameWidge/main/install.sh | bash
```

Then add **FrameWidge** to your panel or system tray via the Plasma widget picker.

### Manual install

1. Install the backend:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/ozturkkl/framework-control/main/install-linux.sh | sudo bash
   ```

2. Install the plasmoid:
   ```bash
   git clone https://github.com/shrippen/FrameWidge.git
   cd FrameWidge
   kpackagetool6 -t Plasma/Applet -i package/
   ```

### Update

```bash
cd FrameWidge && git pull
kpackagetool6 -t Plasma/Applet -u package/
```

## Uninstall

```bash
# Remove the plasmoid
kpackagetool6 -t Plasma/Applet -r org.kde.plasma.frameworkcontrol

# Optionally remove the backend
curl -fsSL https://raw.githubusercontent.com/ozturkkl/framework-control/main/uninstall-linux.sh | sudo bash
```

## Configuration

Right-click the widget → Configure:

| Setting | Default | Description |
|---------|---------|-------------|
| Service port | `30912` | Port of the framework-control service (AUR default) |
| Poll interval | `2000` ms | How often to check service health and poll data |
| Tray display | `temp` | What to show on the compact icon: `temp`, `rpm`, `soc`, or `icon` |

## Architecture

```
┌──────────────────┐       HTTP (127.0.0.1)       ┌─────────────────────────┐
│  Plasma Widget   │ ──────────────────────────── │  framework-control      │
│  (QML)           │    GET/POST /api/*            │  service (Rust/systemd) │
│                  │                               │  → framework_tool CLI   │
└──────────────────┘                               └─────────────────────────┘
```

The widget is a pure QML frontend — no C++ compilation needed. It communicates with the backend via `XMLHttpRequest` to `http://127.0.0.1:<port>/api/`.

## License

MIT — see [LICENSE](LICENSE).

Based on [framework-control](https://github.com/ozturkkl/framework-control) by Kemal Ozturk (MIT License).
