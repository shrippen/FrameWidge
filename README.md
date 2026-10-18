# FrameWidge

> **100% vibe coded.** All code, the landing page and this README were AI-generated. Use at your own risk. Report bugs.

KDE Plasma 6 tray widget for [Framework Laptops](https://frame.work): fan control, power management, battery and sensor telemetry.

> Comes with its own small service, `framewidged`, which talks to the laptop's embedded controller through Framework's `framework_tool`. Parts of it are ported from [ozturkkl/framework-control](https://github.com/ozturkkl/framework-control) by Kemal Ozturk, which FrameWidge used as its backend up to 1.2.

## Features

- **Fan control:** auto, manual duty, drag-and-drop curve editor, hysteresis, rate limiting, per-fan overrides (Framework 16), calibration wizard, curve presets that switch by Plasma Activity or when you plug in or unplug
- **Sensors:** live temperature graphs, sensor selection, configurable time window
- **Power:** the system power profile (power-profiles-daemon or tuned-ppd, the same switch as Plasma's battery applet)
- **Battery:** charge/discharge wattage, health, cycles, charge limit (25–100%), rate limit with SoC threshold
- **Tray:** temperature/RPM/SoC overlay, tooltip with live stats
- **Offline detection:** setup guide when the backend is missing or stopped

## Requirements

- Framework Laptop 13 or 16 (AMD/Intel)
- KDE Plasma 6.1 or newer (Wayland or X11)
- Linux with systemd and polkit; power-profiles-daemon or tuned-ppd for the Power tab
- The `framewidged` service (installed by `install.sh`, see below)

## Install

Installs the service and the widget. A running framework-control is stopped and disabled; its fan, power and battery settings are taken over:

```bash
curl -fsSL https://raw.githubusercontent.com/shrippen/FrameWidge/main/install.sh | bash
```

Then add **FrameWidge** via the Plasma widget picker.

### Manual install

1. Service (needs Rust and [`framework_tool`](https://github.com/FrameworkComputer/framework-system/releases) on PATH or in `/usr/local/lib/framewidge`):
   ```bash
   git clone https://github.com/shrippen/FrameWidge.git
   cd FrameWidge
   cargo build --release --locked --manifest-path service/Cargo.toml
   sudo install -Dm755 service/target/release/framewidged /usr/local/bin/framewidged
   sudo install -Dm644 service/data/framewidged.service /etc/systemd/system/framewidged.service
   sudo install -Dm644 service/data/io.github.shrippen.FrameWidge.conf /etc/dbus-1/system.d/io.github.shrippen.FrameWidge.conf
   sudo install -Dm644 service/data/io.github.shrippen.FrameWidge.policy /usr/share/polkit-1/actions/io.github.shrippen.FrameWidge.policy
   sudo systemctl reload dbus && sudo systemctl daemon-reload && sudo systemctl enable --now framewidged
   ```

2. Plasmoid:
   ```bash
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

# Service (optional; stopping it hands the fans back to the firmware)
sudo systemctl disable --now framewidged
sudo rm -f /usr/local/bin/framewidged /etc/systemd/system/framewidged.service \
    /etc/dbus-1/system.d/io.github.shrippen.FrameWidge.conf \
    /usr/share/polkit-1/actions/io.github.shrippen.FrameWidge.policy
sudo rm -rf /var/lib/framewidged /usr/local/lib/framewidge
```

## Configuration

Right-click the widget → Configure.

| Setting | Default | Description |
|---------|---------|-------------|
| Poll interval | `2000` ms | Health check and data polling interval |
| Tray display | `temp` | Compact icon content: `temp`, `rpm`, `soc`, `icon` |
| Style | System | Popup look: System (Plasma theme), Kante, Kante Light |

The popup follows your Plasma theme by default. Kante and Kante Light are opt-in: they use the [Kante](https://github.com/shrippen/shrippen.github.io) QML module, vendored unchanged in `package/contents/ui/Kante` and `KantePlasma` (`scripts/sync-kante.sh` refreshes it). The tray icon keeps the Plasma look; the settings page shows the Kante band editor when it runs in the same Kante style as the popup.

## Translations

The widget is in English and German. `po/update.sh` extracts the `i18n()` strings into
`po/framewidge.pot`, merges them into every `po/<lang>.po` and compiles
`package/contents/locale/<lang>/LC_MESSAGES/plasma_applet_org.kde.plasma.framewidge.mo`, which ships
with the package. Add a language by copying the template to `po/<lang>.po` and running the script.

## Architecture

```
┌──────────────────┐   D-Bus (system bus)   ┌──────────────────────────┐
│  Plasma Widget   │ ─────────────────────▶ │  framewidged             │
│  (QML)           │ io.github.shrippen.    │  service (Rust/systemd)  │
│                  │   FrameWidge1          │  reads: sysfs            │
└──────────────────┘                        │  writes: framework_tool  │
                                            │  → EC; power profile →   │
                                            │  power-profiles-daemon   │
                                            └──────────────────────────┘
```

The widget is pure QML and calls the service over the system D-Bus. Reading is open to every local user; changing settings asks polkit, which allows it for the person at the laptop without a password. The service (`service/`) runs as root, keeps the fan curve and charge limit applied without the widget, switches curve presets with the power source, and stores its settings in `/var/lib/framewidged/config.json`. See [DESIGN.md](DESIGN.md).

## License

MIT, see [LICENSE](LICENSE). The service ports parts of [framework-control](https://github.com/ozturkkl/framework-control) by Kemal Ozturk (MIT).
